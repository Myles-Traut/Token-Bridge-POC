// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {UniswapDeployer} from "../script/UniswapDeployer.s.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {Token} from "../src/Token.sol";
import {TokenSwap} from "../src/TokenSwap.sol";

contract UniswapTests is Test {
    IUniswapV2Factory public factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    WETH public weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 public router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    TokenSwap public tokenSwap;
    Token public token;
    Token public token2;

    address user = makeAddr("user");

    function setUp() public {
        UniswapDeployer deployer = new UniswapDeployer();
        tokenSwap = new TokenSwap(address(router));
        deployer.run();

        token = new Token();
        weth.deposit{value: 10 ether}();

        token.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);

        IUniswapV2Router01(router).addLiquidity(
            address(token),
            address(weth),
            token.balanceOf(address(this)), 
            weth.balanceOf(address(this)), 
            0,
            0,
            address(this),
            block.timestamp + 1000
        );

        deal(user, 10 ether);
        token.mint(user, 10 ether);
    }

    function test_TokenSwap() public {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        assertEq(address(tokenSwap.router()), address(router));
        vm.startPrank(user);
        token.approve(address(tokenSwap), 1 ether);
        uint256[] memory amounts = tokenSwap.swapExactTokensForTokens(1 ether, 0, path, user, block.timestamp + 1000);
        console.logUint(amounts[1]);
        console.logUint(token.balanceOf(user));
        console.logUint(weth.balanceOf(user));
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

    // function test_addLiquidity() public {
    //     Token token = new Token();

    //     token.approve(address(router), type(uint256).max);
        
    //     IUniswapV2Router01(router).addLiquidityETH{value: 10 ether}(
    //         address(token), 
    //         token.balanceOf(address(this)), 
    //         0,
    //         0,
    //         address(this),
    //         block.timestamp + 1000
    //     );
    // }
}
