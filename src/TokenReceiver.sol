// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;
pragma abicoder v2;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import {ITokenReceiver} from "./interfaces/ITokenReceiver.sol";

contract TokenReceiver is CCIPReceiver, ITypeAndVersion, ITokenReceiver, Ownable, ReentrancyGuard, Pausable {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    IRouterClient public ccipRouter;
    IUniswapV2Router02 public swapRouter;
    IWrappedNative public weth;

    string public constant override typeAndVersion = "TokenTransfer V1.0";

    bytes32 private _lastReceivedMessageId;
    uint256 private _lastReceivedTokenAmount;
    address private _lastReceivedTokenAddress;

    // Keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    // The message contents of failed messages are stored here.
    mapping(bytes32 => Client.Any2EVMMessage) public messageContents;

    // Contains failed messages and their state.
    EnumerableMap.Bytes32ToUintMap internal _failedMessages;

    constructor(IUniswapV2Router02 _swapRouter, address _ccipRouter, address _weth)
        checkZeroAddress(_weth)
        checkZeroAddress(_ccipRouter)
        CCIPReceiver(_ccipRouter)
        Ownable(msg.sender)
    {
        ccipRouter = IRouterClient(_ccipRouter);
        swapRouter = _swapRouter;
        weth = IWrappedNative(payable(_weth));
        weth.approve(_ccipRouter, type(uint256).max);
    }

    /*----------- Admin Functions ----------- */

    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = _allowed;

        emit SourceChainAllowlisted(_sourceChainSelector, _allowed);
    }

    function allowlistSender(address _sender, bool _allowed) external onlyOwner checkZeroAddress(_sender) {
        allowlistedSenders[_sender] = _allowed;

        emit SenderAllowlisted(_sender, _allowed);
    }

    function setRouter(address _router) external onlyOwner checkZeroAddress(_router) {
        ccipRouter = IRouterClient(_router);

        emit RouterSet(_router);
    }

    function setWeth(address _WETH) external onlyOwner checkZeroAddress(_WETH) {
        weth = IWrappedNative(payable(_WETH));

        emit WETHSet(_WETH);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /*---------- CCIP Functions ----------*/

    /// @notice The entrypoint for the CCIP router to call. This function should never revert.
    /// @param message The message to process.
    /// @dev Extremely important to ensure only router calls this.
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        onlyRouter
        onlyAllowlisted(message.sourceChainSelector, abi.decode(message.sender, (address)))
        whenNotPaused
    {
        /* solhint-disable no-empty-blocks */
        try this.processMessage(message) {}
        catch (bytes memory err) {
            _failedMessages.set(message.messageId, uint256(ErrorCode.FAILED));
            messageContents[message.messageId] = message;
            // Don't revert so CCIP doesn't revert. Emit event instead.
            // The message can be retried later without having to do manual execution of CCIP.
            emit MessageFailed(message.messageId, err);
            return;
        }
    }

    function processMessage(Client.Any2EVMMessage calldata _message)
        external
        onlySelf
        onlyAllowlisted(_message.sourceChainSelector, abi.decode(_message.sender, (address)))
        whenNotPaused
    {
        _ccipReceive(_message);
    }

    function retryFailedMessage(bytes32 messageId) external nonReentrant {
        if (!_failedMessages.contains(messageId)) {
            revert MessageNotFound(messageId);
        }
        if (_failedMessages.get(messageId) != uint256(ErrorCode.FAILED)) {
            revert MessageNotFailed(messageId);
        }

        _failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

        Client.Any2EVMMessage memory message = messageContents[messageId];

        _executeMessage(message);

        emit MessageRecovered(messageId);
    }

    /*----------  Internal Functions  ----------*/

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256[] memory amounts) {
        ERC20(path[0]).approve(address(swapRouter), amountIn);
        return swapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function _executeMessage(Client.Any2EVMMessage memory _message) internal nonReentrant returns (uint256 tokenAmount) {
        SwapDetails memory details = abi.decode(_message.data, (SwapDetails));

        uint256 wethAmount = _message.destTokenAmounts[0].amount;

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = details.originalToken;

        address pair = IUniswapV2Factory(swapRouter.factory()).getPair(address(weth), details.originalToken);
        if (pair == address(0)) revert PairDoesNotExist(address(weth), details.originalToken);

        uint256[] memory amounts =
            _swapExactTokensForTokens(wethAmount, details.minAmountOut, path, details.recipient, details.deadline);

        tokenAmount = amounts[1];

        _lastReceivedMessageId = _message.messageId;
        _lastReceivedTokenAmount = tokenAmount;
        _lastReceivedTokenAddress = details.originalToken;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
        onlyAllowlisted(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        uint256 tokenAmount = _executeMessage(message);

        emit MessageReceived(
            message.messageId,
            message.sourceChainSelector,
            abi.decode(message.sender, (address)),
            tokenAmount,
            _lastReceivedTokenAddress
        );
    }

    /*----------  View Functions  ----------*/

    /**
     * @notice Returns the details of the last CCIP received message.
     */
    function getLastReceivedMessageDetails()
        public
        view
        returns (bytes32 messageId, address tokenAddress, uint256 tokenAmount)
    {
        return (_lastReceivedMessageId, _lastReceivedTokenAddress, _lastReceivedTokenAmount);
    }

    function getFailedMessages(uint256 offset, uint256 limit) external view returns (FailedMessage[] memory) {
        uint256 length = _failedMessages.length();

        // Calculate the actual number of items to return (can't exceed total length or requested limit)
        uint256 returnLength = (offset + limit > length) ? length - offset : limit;
        FailedMessage[] memory failedMessages = new FailedMessage[](returnLength);

        // Adjust loop to respect pagination (start at offset, end at offset + limit or total length)
        for (uint256 i = 0; i < returnLength; i++) {
            (bytes32 messageId, uint256 errorCode) = _failedMessages.at(offset + i);
            failedMessages[i] = FailedMessage(messageId, ErrorCode(errorCode));
        }
        return failedMessages;
    }

    /*----------  Modifiers  ----------*/

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector]) {
            revert SourceChainNotAllowed(_sourceChainSelector);
        }
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }
    /**
     * @dev Modifier to allow only the contract itself to execute a function.
     * Throws an exception if called by any account other than the contract itself.
     */

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }
}
