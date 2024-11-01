// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
pragma abicoder v2;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ITokenSender} from "./interfaces/ITokenSender.sol";

contract TokenSender is ITokenSender, ReentrancyGuard, Ownable, Pausable {
    IUniswapV2Router02 public swapRouter;
    IUniswapV2Factory public factory;
    IRouterClient public ccipRouter;
    IWrappedNative public weth;

    address public messageReceiver;
    address public feeToken_;

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    constructor(
        IUniswapV2Router02 _swapRouter,
        address _factory,
        address _WETH9,
        address _ccipRouter,
        address _link,
        address _receiver,
        address _owner
    )
        checkZeroAddress(address(_swapRouter))
        checkZeroAddress(_factory)
        checkZeroAddress(_WETH9)
        checkZeroAddress(_ccipRouter)
        checkZeroAddress(_link)
        checkZeroAddress(_receiver)
        Ownable(_owner)
    {
        swapRouter = _swapRouter;
        factory = IUniswapV2Factory(_factory);
        weth = IWrappedNative(payable(_WETH9));
        messageReceiver = _receiver;
        feeToken_ = _link;
        ccipRouter = IRouterClient(_ccipRouter);
    }

    /*----------- Admin Functions ----------- */

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool _allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = _allowed;

        emit DestinationChainAllowlisted(_destinationChainSelector, _allowed);
    }

    function setFeeToken(address _feeToken) external onlyOwner checkZeroAddress(_feeToken) {
        address oldFeeToken = feeToken_;
        feeToken_ = _feeToken;
        emit FeeTokenSet(oldFeeToken, feeToken_);
    }

    function setWeth(address _WETH) external checkZeroAddress(_WETH) onlyOwner {
        weth = IWrappedNative(payable(_WETH));

        emit WETHSet(_WETH);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function recoverToken(address _token, uint256 _amount) external checkZeroAddress(_token) onlyOwner {
        if (_token == address(weth)) revert WETHNotAllowed();
        if (_amount == 0) revert ZeroAmount();
        ERC20(_token).transfer(owner(), _amount);
        emit TokenRecovered(_token, _amount);
    }

    /*----------- Public Functions ----------- */

    ///@notice Make sure this contract has enough LINK to pay for fees
    function bridge(
        uint64 _destinationChainSelector,
        address _tokenAddress,
        uint256 _tokenAmountIn,
        uint256 _minAmountOut,
        uint256 _deadline,
        bytes memory _extraArgs
    )
        external
        whenNotPaused
        onlyAllowlistedChain(_destinationChainSelector)
        checkZeroAddress(_tokenAddress)
        nonReentrant
        returns (bytes32 messageId)
    {
        if (_tokenAddress == address(weth)) revert WETHNotAllowed();
        if (_tokenAmountIn == 0) revert ZeroAmount();
        if (_deadline <= block.timestamp) revert DeadlinePassed(_deadline, block.timestamp);

        address[] memory path = _encodePathAndValidatePair(_tokenAddress, _tokenAmountIn);

        uint256[] memory amounts =
            _swapExactTokensForTokens(_tokenAmountIn, _minAmountOut, path, address(this), _deadline);

        SwapDetails memory details =
            SwapDetails({originalToken: _tokenAddress, minAmountOut: _minAmountOut, deadline: _deadline, recipient: msg.sender});

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(amounts[1], abi.encode(details), _extraArgs);

        uint256 fee = ccipRouter.getFee(_destinationChainSelector, message);

        if (ERC20(feeToken_).balanceOf(address(this)) < fee) {
            revert InsufficientFeeTokenBalance(fee, ERC20(feeToken_).balanceOf(address(this)));
        }

        ERC20(feeToken_).approve(address(ccipRouter), fee);
        weth.approve(address(ccipRouter), amounts[1]);

        messageId = ccipRouter.ccipSend(_destinationChainSelector, message);

        emit MessageSent(messageId, _destinationChainSelector, message.tokenAmounts[0].amount, feeToken_, fee);
    }

    /*---------- Internal Functions ----------*/

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256[] memory amounts) {
        ERC20 token = ERC20(path[0]);
        token.transferFrom(msg.sender, address(this), amountIn);
        token.approve(address(swapRouter), amountIn);
        return swapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    /// @notice Construct a CCIP message.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(uint256 _wethAmount, bytes memory _data, bytes memory _extraArgs)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);

        tokenAmounts[0] = Client.EVMTokenAmount({token: address(weth), amount: _wethAmount});

        return Client.EVM2AnyMessage({
            receiver: abi.encode(messageReceiver),
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: _extraArgs,
            feeToken: feeToken_
        });
    }

    function _encodePathAndValidatePair(address _tokenAddress, uint256 _tokenAmountIn)
        internal
        view
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = _tokenAddress;
        path[1] = address(weth);

        address pair = factory.getPair(_tokenAddress, address(weth));

        if (pair == address(0)) {
            revert PairNotFound(_tokenAddress, address(weth));
        }

        // Get the pair contract
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(pair);

        // Get token ordering in the pair
        address token0 = uniswapPair.token0();

        // Get reserves
        (uint256 reserve0, uint256 reserve1,) = uniswapPair.getReserves();

        // Check the correct reserve based on token ordering
        uint256 relevantReserve = token0 == _tokenAddress ? reserve0 : reserve1;

        if (relevantReserve < _tokenAmountIn) {
            revert InsufficientLiquidity(relevantReserve);
        }
    }

    /*----------  View Functions  ----------*/

    function getFee(
        uint64 _destinationChainSelector,
        address _tokenAddress,
        uint256 _minAmountOut,
        uint256 _deadline,
        uint256 _wethAmount,
        bytes memory _data,
        bytes memory _extraArgs
    ) external view returns (uint256) {
        SwapDetails memory details =
            SwapDetails({originalToken: _tokenAddress, minAmountOut: _minAmountOut, deadline: _deadline, recipient: msg.sender});

        ccipRouter.getFee(_destinationChainSelector, _buildCCIPMessage(_wethAmount, _data, _extraArgs));
    }

    function getFeeToken() public view returns (address) {
        return feeToken_;
    }

    /*----------  Modifiers  ----------*/

    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        }
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }
}
