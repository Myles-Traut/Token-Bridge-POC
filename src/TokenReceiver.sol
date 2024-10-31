// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;
pragma abicoder v2;

// import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract TokenReceiver is CCIPReceiver, ITypeAndVersion {
    // using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /*----------  Events  ----------*/

    event WETHSet(address indexed weth);

    event MessageFailed(bytes32 indexed messageId, bytes reason);
    event MessageRecovered(bytes32 indexed messageId);
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 tokenAmount,
        address tokenAddress
    );
    event SourceChainAllowlisted(uint64 indexed sourceChainSelector, bool allowed);
    event SenderAllowlisted(address indexed sender, bool allowed);
    event RouterSet(address indexed router);

    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error ZeroAddress();
    error SenderNotAllowed(address sender);
    error OnlySelf();
    error MessageNotFound(bytes32 messageId);
    error MessageNotFailed(bytes32 messageId);

    enum ErrorCode {
        RESOLVED,
        FAILED
    }

    struct FailedMessage {
        bytes32 messageId;
        ErrorCode errorCode;
    }

    struct SwapDetails {
        address originalToken;
        uint256 minAmountOut;
        address recipient;
    }

    string public constant override typeAndVersion = "TokenTransfer V1.0";

    IRouterClient public ccipRouter;
    IUniswapV2Router02 public swapRouter;
    IWrappedNative public weth;

    bytes32 private _lastReceivedMessageId;
    uint256 private _lastReceivedTokenAmount;
    address private _lastReceivedTokenAddress;

    uint24 public constant poolFee = 3000; // 0.3% fee

    // Keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    // The message contents of failed messages are stored here.
    mapping(bytes32 => Client.Any2EVMMessage) public messageContents;

    // Contains failed messages and their state.
    // EnumerableMap.Bytes32ToUintMap internal _failedMessages;

    constructor(IUniswapV2Router02 _swapRouter, address _ccipRouter, address _weth) CCIPReceiver(_ccipRouter) {
        ccipRouter = IRouterClient(_ccipRouter);
        swapRouter = _swapRouter;
        weth = IWrappedNative(payable(_weth));
        weth.approve(_ccipRouter, type(uint256).max);
    }

    /*----------- Admin Functions ----------- */

    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external {
        allowlistedSourceChains[_sourceChainSelector] = _allowed;

        emit SourceChainAllowlisted(_sourceChainSelector, _allowed);
    }

    function allowlistSender(address _sender, bool _allowed) external checkZeroAddress(_sender) {
        allowlistedSenders[_sender] = _allowed;

        emit SenderAllowlisted(_sender, _allowed);
    }

    function setRouter(address _router) external {
        ccipRouter = IRouterClient(_router);

        emit RouterSet(_router);
    }

    function setWeth(address _WETH) external checkZeroAddress(_WETH) {
        weth = IWrappedNative(payable(_WETH));

        emit WETHSet(_WETH);
    }

    /*---------- Uniswap Functions ----------*/
    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256[] memory amounts) {
        // ERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        ERC20(path[0]).approve(address(swapRouter), amountIn);
        return swapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    /*---------- CCIP Functions ----------*/

    /**
     * @notice The entrypoint for the CCIP router to call. This function should  never revert.
     * All errors should be handled internally in this contract.
     * @param message The message to process.
     * @dev Extremely important to ensure only router calls this.
     */
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        onlyRouter
        onlyAllowlisted(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        /* solhint-disable no-empty-blocks */
        try this.processMessage(message) {}
        catch (bytes memory err) {
            // _failedMessages.set(message.messageId, uint256(ErrorCode.FAILED));
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
    {
        _ccipReceive(_message);
    }

    //   function retryFailedMessage(
    //     bytes32 messageId
    //   ) external {
    //     if (!_failedMessages.contains(messageId)) {
    //       revert MessageNotFound(messageId);
    //     }
    //     if (_failedMessages.get(messageId) != uint256(ErrorCode.FAILED)) {
    //       revert MessageNotFailed(messageId);
    //     }

    //     // Set the error code to RESOLVED to disallow reentry and multiple retries of the same failed message.
    //     _failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

    //     Client.Any2EVMMessage memory message = messageContents[messageId];

    //     _executeMessage(message);

    //     emit MessageRecovered(messageId);
    //   }

    /*----------  Internal Functions  ----------*/

    function _executeMessage(Client.Any2EVMMessage memory _message) internal returns (uint256 tokenAmount) {
        SwapDetails memory details = abi.decode(_message.data, (SwapDetails));

        uint256 wethAmount = _message.destTokenAmounts[0].amount;

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = details.originalToken;

        uint256[] memory amounts =
            _swapExactTokensForTokens(wethAmount, details.minAmountOut, path, details.recipient, block.timestamp + 1000);

        tokenAmount = amounts[1];

        _lastReceivedMessageId = _message.messageId;
        _lastReceivedTokenAmount = tokenAmount;
        _lastReceivedTokenAddress = details.originalToken;
    }

    /// @notice Receive the wrapped ether and unwraps it.
    /// @notice Receive the lastest unbackedRswETH amount and transfers it to the oft adaptor / lockbox.
    /// @param message The CCIP message containing the wrapped ether amount, ETH amount wrapped on L2 and the unbackedRswETH amount.
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

    /*----------  Public View Functions  ----------*/

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

    //   /**
    //    * @notice Retrieves a paginated list of failed messages.
    //    * @dev This function returns a subset of failed messages defined by `offset` and `limit` parameters. It ensures that the pagination parameters are within the bounds of the available data set.
    //    * @param offset The index of the first failed message to return, enabling pagination by skipping a specified number of messages from the start of the dataset.
    //    * @param limit The maximum number of failed messages to return, restricting the size of the returned array.
    //    * @return failedMessages An array of `FailedMessage` struct, each containing a `messageId` and an `errorCode` (RESOLVED or FAILED), representing the requested subset of failed messages. The length of the returned array is determined by the `limit` and the total number of failed messages.
    //    */
    //   function getFailedMessages(
    //     uint256 offset,
    //     uint256 limit
    //   ) external view returns (FailedMessage[] memory) {
    //     uint256 length = _failedMessages.length();

    //     // Calculate the actual number of items to return (can't exceed total length or requested limit)
    //     uint256 returnLength = (offset + limit > length) ? length - offset : limit;
    //     FailedMessage[] memory failedMessages = new FailedMessage[](returnLength);

    //     // Adjust loop to respect pagination (start at offset, end at offset + limit or total length)
    //     for (uint256 i = 0; i < returnLength; i++) {
    //       (bytes32 messageId, uint256 errorCode) = _failedMessages.at(offset + i);
    //       failedMessages[i] = FailedMessage(messageId, ErrorCode(errorCode));
    //     }
    //     return failedMessages;
    //   }

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
