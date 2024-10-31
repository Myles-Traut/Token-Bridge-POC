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
import {TokenSender} from "../src/TokenSender.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";

import {IRouterClient, LinkToken, WETH9} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract TokenBridgeTests is Test {
    IUniswapV2Factory public factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    WETH public weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 public router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    Token public token;
    TokenSender public tokenSender;
    TokenReceiver public tokenReceiver;

    CCIPLocalSimulator public ccipLocalSimulator;

    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    IRouterClient public destinationRouter;
    WETH9 public wrappedNative;
    LinkToken public linkToken;

    address user = makeAddr("user");
    address owner = makeAddr("owner");

    struct EVMTokenAmount {
        address token; // token address on the local chain.
        uint256 amount; // Amount of tokens.
    }

    function setUp() public {
        UniswapDeployer deployer = new UniswapDeployer();
        deployer.run();

        ccipLocalSimulator = new CCIPLocalSimulator();

        (chainSelector, sourceRouter, destinationRouter, wrappedNative, linkToken,,) =
            ccipLocalSimulator.configuration();

        vm.startPrank(owner);

        tokenReceiver = new TokenReceiver(router, address(sourceRouter), address(weth));
        tokenSender = new TokenSender(
            router, address(weth), address(destinationRouter), address(linkToken), address(tokenReceiver), owner
        );
        ccipLocalSimulator.requestLinkFromFaucet(address(tokenSender), 5 ether);
        assertEq(linkToken.balanceOf(address(tokenSender)), 5 ether);

        token = new Token();

        deal(owner, 10 ether);
        weth.deposit{value: 10 ether}();

        token.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);

        IUniswapV2Router01(router).addLiquidity(
            address(token),
            address(weth),
            token.balanceOf(owner),
            weth.balanceOf(owner),
            0,
            0,
            owner,
            block.timestamp + 1000
        );

        deal(user, 10 ether);
        token.mint(user, 1 ether);

        vm.stopPrank();
    }

    function test_TokenSender() public {
        vm.startPrank(owner);
        tokenSender.allowlistDestinationChain(chainSelector, true);
        tokenReceiver.allowlistSourceChain(chainSelector, true);
        tokenReceiver.allowlistSender(address(tokenSender), true);
        vm.stopPrank();

        // Additional arguments, setting gas limit
        bytes memory extraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}));

        assertEq(token.balanceOf(user), 1 ether);

        vm.startPrank(user);
        token.approve(address(tokenSender), 1 ether);
        tokenSender.bridge(chainSelector, address(token), 1 ether, 1, extraArgs);
        vm.stopPrank();

        uint256 amountAfterFee1 = _calculateAmountAfterFee(1 ether, 30);
        uint256 amountAfterFee2 = _calculateAmountAfterFee(amountAfterFee1, 30);

        assertGe(token.balanceOf(user), amountAfterFee2);

        (bytes32 messageId, address tokenAddress, uint256 tokenAmount) = tokenReceiver.getLastReceivedMessageDetails();

        assertEq(tokenAddress, address(token));
        assertEq(tokenAmount, token.balanceOf(user));
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

    function _calculateAmountAfterFee(uint256 amountIn, uint24 fee) internal pure returns (uint256) {
        // fee is in basis points (e.g., 30 = 0.3%)
        uint256 feeMultiplier = 10000 - fee; // for 0.3% fee: 10000 - 30 = 9970
        return (amountIn * feeMultiplier) / 10000;
    }
}
