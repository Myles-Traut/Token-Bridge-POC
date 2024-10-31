// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ITokenSender {
    /*---------- EVENTS ----------*/
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

    /*---------- ERRORS ----------*/
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error ZeroAddress();
    error Unauthorized(address sender);

    /*---------- STORAGE ----------*/
    struct SwapDetails {
        address originalToken;
        uint256 minAmountOut;
        address recipient;
    }
}
