// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
contract TokenSwap {
    IUniswapV2Router02 public immutable router;

    constructor(address _router) {
        router = IUniswapV2Router02(_router);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        ERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        ERC20(path[0]).approve(address(router), amountIn);
        return router.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }
}
