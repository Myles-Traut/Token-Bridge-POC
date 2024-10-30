// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract TokenSwap {
    IUniswapV2Router02 public immutable router;

    constructor(address _router) {
        router = IUniswapV2Router02(_router);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        return router.swapExactETHForTokens{value: msg.value}(amountOutMin, path, to, deadline);
    }
}
