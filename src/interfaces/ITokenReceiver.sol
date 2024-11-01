// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

interface ITokenReceiver {
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

    /*----------  Errors  ----------*/

    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error ZeroAddress();
    error SenderNotAllowed(address sender);
    error OnlySelf();
    error MessageNotFound(bytes32 messageId);
    error MessageNotFailed(bytes32 messageId);
    error PairDoesNotExist(address token0, address token1);

    /*----------  Storage  ----------*/

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
        uint256 deadline;
        address recipient;
    }

    /*----------  Functions  ----------*/

    /// @notice Returns the WETH contract
    /// @return The WETH contract
    function weth() external view returns (IWrappedNative);

    /// @notice Allows or disallows a source chain
    /// @param _sourceChainSelector The chain selector to allow or disallow
    /// @param _allowed Whether to allow or disallow the chain
    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external;

    /// @notice Allows or disallows a sender
    /// @param _sender The sender to allow or disallow
    /// @param _allowed Whether to allow or disallow the sender
    function allowlistSender(address _sender, bool _allowed) external;

    /// @notice Sets the router
    /// @param _router The router to set
    function setRouter(address _router) external;

    /// @notice Sets the WETH contract
    /// @param _WETH The WETH contract to set
    function setWeth(address _WETH) external;

    /// @notice Processes a CCIP message
    /// @param _message The CCIP message to process
    function processMessage(Client.Any2EVMMessage calldata _message) external;

    /// @notice Returns the details of the last received message
    /// @return messageId The message ID
    /// @return tokenAddress The token address
    /// @return tokenAmount The token amount
    function getLastReceivedMessageDetails() external view returns (bytes32 messageId, address tokenAddress, uint256 tokenAmount);

    /// @notice Retrieves a paginated list of failed messages.
    /// @dev This function returns a subset of failed messages defined by `offset` and `limit` parameters. It ensures that the pagination parameters are within the bounds of the available data set.
    /// @param offset The index of the first failed message to return, enabling pagination by skipping a specified number of messages from the start of the dataset.
    /// @param limit The maximum number of failed messages to return, restricting the size of the returned array.
    /// @return failedMessages An array of `FailedMessage` struct, each containing a `messageId` and an `errorCode` (RESOLVED or FAILED), representing the requested subset of failed messages. The length of the returned array is determined by the `limit` and the total number of failed messages.
    function getFailedMessages(uint256 offset, uint256 limit) external view returns (FailedMessage[] memory);
}
