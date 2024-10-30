// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract TokenSender {

    event DestinationChainAllowlisted(uint64 indexed destinationChainSelector, bool allowed);
    event FeeTokenSet(address indexed oldFeeToken, address indexed newFeeToken);
    event WETHSet(address indexed weth);
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error ZeroAddress();

    IUniswapV2Router02 public swapRouter;
    IRouterClient public ccipRouter;
    IWrappedNative public weth;
    address public receiver;
    // uint24 public constant poolFee = 3000; // 0.3% fee

    address public feeToken_;

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    

    constructor(IUniswapV2Router02 _swapRouter, address _WETH9, address _ccipRouter, address _link, address _receiver) {
        swapRouter = _swapRouter;
        weth = IWrappedNative(payable(_WETH9));
        receiver = _receiver;
        feeToken_ = _link;
        ccipRouter = IRouterClient(_ccipRouter);
    }

    /*----------- Admin Functions ----------- */

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool _allowed
    ) external {
        allowlistedDestinationChains[_destinationChainSelector] = _allowed;

        emit DestinationChainAllowlisted(_destinationChainSelector, _allowed);
    }

    function setFeeToken(
        address _feeToken
    ) external {
        address oldFeeToken = feeToken_;
        feeToken_ = _feeToken;
        emit FeeTokenSet(oldFeeToken, feeToken_);
    }

    function setWeth(
        address _WETH
    ) external checkZeroAddress(_WETH) {
        weth = IWrappedNative(payable(_WETH));

        emit WETHSet(_WETH);
    }

    /*----------- Public Functions ----------- */

    function bridge(
        uint64 _destinationChainSelector,
        address _tokenAddress, 
        uint256 _tokenAmountIn
        // bytes memory _extraArgs
    )
        external
        onlyAllowlistedChain(_destinationChainSelector)
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = _tokenAddress;
        path[1] = address(weth);

        uint256[] memory amounts = _swapExactTokensForTokens(_tokenAmountIn, 0, path, address(this), block.timestamp + 1000);

        // Client.EVM2AnyMessage memory message = _buildCCIPMessage(
        //     amounts[1],
        //     abi.encode(_tokenAddress),
        //     _extraArgs
        // );

        // ERC20 feeToken = ERC20(message.feeToken);

        // uint256 fee = ccipRouter.getFee(_destinationChainSelector, message);

        // We need to transfer the fee to this contract and re-approve it to the router.
        // Its not possible to have any leftover tokens in this path because we transferFrom the exact fee that CCIP
        // requires from the caller.
        // feeToken.approve(address(ccipRouter), fee);
        // feeToken.transferFrom(msg.sender, address(this), fee);

        return amounts[1];

        // bytes32 messageId = ccipRouter.ccipSend(_destinationChainSelector, message);

        // emit MessageSent(
        //     messageId,
        //     _destinationChainSelector,
        //     message.tokenAmounts[0].amount,
        //     address(feeToken),
        //     fee
        // );

        // return messageId;
    }

    /*---------- Internal Functions ----------*/

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin, 
        address[] memory path, 
        address to, 
        uint256 deadline
    ) internal returns (uint256[] memory amounts) {
        ERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        ERC20(path[0]).approve(address(swapRouter), amountIn);
        return swapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

     /// @notice Construct a CCIP message.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.

    function _buildCCIPMessage(
        uint256 _tokenAmount,
        bytes memory _data,
        bytes memory _extraArgs
    ) internal view returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);

        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(weth),
            amount: _tokenAmount
        });

        return
        Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: _extraArgs,
            feeToken: feeToken_
        });
    }

    /*----------  View Functions  ----------*/

      function getFee(
        uint64 _destinationChainSelector,
        uint256 _tokenAmount,
        bytes memory _data,
        bytes memory _extraArgs
    ) external view returns (uint256) {
        return
        ccipRouter.getFee(
            _destinationChainSelector,
            _buildCCIPMessage(
                _tokenAmount,
                _data,
                _extraArgs
            )
        );
    }

    function getFeeToken() public view returns (address) {
        return feeToken_;
    }

    /*----------  Modifiers  ----------*/

    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
    if (!allowlistedDestinationChains[_destinationChainSelector])
      revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    modifier checkZeroAddress(address _address) {
    if (_address == address(0)) revert ZeroAddress();
        _;
    }
}
