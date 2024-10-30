// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {UniswapDeployer} from "../script/UniswapDeployer.s.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {Token} from "../src/Token.sol";

contract UniswapTests is Test {
    IUniswapV2Factory public factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    WETH public weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 public router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    function setUp() public {
        UniswapDeployer deployer = new UniswapDeployer();
        deployer.run();
    }

    function test_UniswapFactory() public {
        assertEq(factory.feeToSetter(), address(0x1111111111111111111111111111111111111111));
    }

    function test_WETH() public {
        assertEq(weth.decimals(), 18);
        assertEq(weth.symbol(), "WETH");
        assertEq(weth.name(), "Wrapped Ether");
    }

    function test_UniswapRouter() public {
        assertEq(router.factory(), address(factory));
        assertEq(router.WETH(), address(weth));
    }

    function test_addLiquidity() public {
        Token token = new Token();

        token.approve(address(router), type(uint256).max);
        
        IUniswapV2Router01(router).addLiquidityETH{value: 10 ether}(
            address(token), 
            token.balanceOf(address(this)), 
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
    }
}
