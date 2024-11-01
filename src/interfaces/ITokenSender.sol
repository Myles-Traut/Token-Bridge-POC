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
    event TokenRecovered(address indexed token, uint256 amount);

    /*---------- ERRORS ----------*/

    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error ZeroAddress();
    error Unauthorized(address sender);
    error PairNotFound(address tokenAddress, address weth);
    error InsufficientLiquidity(uint256 reserve0);
    error WETHNotAllowed();
    error ZeroAmount();
    error InsufficientFeeTokenBalance(uint256 required, uint256 balance);
    error DeadlinePassed(uint256 deadline, uint256 timestamp);

    /*---------- STORAGE ----------*/

    /// @notice Details about the swap
    /// @custom:field originalToken The address of the token being bridged
    /// @custom:field minAmountOut The minimum amount of weth the token will be swapped for on uniswap
    /// @custom:field deadline The deadline for the uniswap swap
    /// @custom:field recipient The recipient of the bridged funds
    struct SwapDetails {
        address originalToken;
        uint256 minAmountOut;
        uint256 deadline;
        address recipient;
    }

    /*---------- FUNCTIONS ----------*/

    /// @notice Allows or disallows a destination chain for CCIP transfers
    /// @notice _destinationChainSelector is unique to chainlink and not the same as a chainId
    /// @dev Only callable by the contract owner
    /// @param _destinationChainSelector The selector of the destination chain to be configured
    /// @param _allowed True to allow the chain, false to disallow
    /// @custom:event DestinationChainAllowlisted
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool _allowed) external;

    /// @notice Sets the fee token for CCIP transfers
    /// @dev Only callable by the contract owner
    /// @param _feeToken The address of the fee token to be set
    /// @custom:event FeeTokenSet
    /// @custom:error ZeroAddress if the provided address is zero
    function setFeeToken(address _feeToken) external;

    /// @notice Sets the WETH token for CCIP transfers
    /// @dev Only callable by the contract owner
    /// @param _weth The address of the WETH token to be set
    /// @custom:event WETHSet
    /// @custom:error ZeroAddress if the provided address is zero
    function setWeth(address _weth) external;

    /// @notice Pauses the contract
    /// @dev Only callable by the contract owner
    /// @custom:event Paused
    function pause() external;

    /// @notice Unpauses the contract
    /// @dev Only callable by the contract owner
    /// @custom:event Unpaused
    function unpause() external;

    /// @notice Recovers a token from the contract
    /// @dev Only callable by the contract owner
    /// @param _token The address of the token to be recovered
    /// @param _amount The amount of the token to be recovered
    /// @custom:event TokenRecovered
    /// @custom:error ZeroAddress if the provided address is zero
    /// @custom:error ZeroAmount if the provided amount is zero
    /// @custom:error WETHNotAllowed if the token being recovered is WETH
    function recoverToken(address _token, uint256 _amount) external;

    /// @notice Bridges a token to a destination chain
    /// @param _destinationChainSelector The selector of the destination chain to be configured
    /// @param _tokenAddress The address of the token to be bridged
    /// @param _tokenAmountIn The amount of the token to be bridged
    /// @param _minAmountOut The minimum amount of weth the token will be swapped for on uniswap
    /// @param _deadline The deadline for the uniswap swap
    /// @param _extraArgs Additional arguments for the bridge transaction such as gas limit
    /// @return messageId The messageId of the bridge transaction
    /// @custom:event MessageSent
    /// @custom:error DestinationChainNotAllowlisted if the destination chain is not allowlisted
    /// @custom:error ZeroAddress if the provided address is zero
    /// @custom:error ZeroAmount if the provided amount is zero
    /// @custom:error DeadlinePassed if the deadline has passed
    function bridge(
        uint64 _destinationChainSelector,
        address _tokenAddress,
        uint256 _tokenAmountIn,
        uint256 _minAmountOut,
        uint256 _deadline,
        bytes memory _extraArgs
    ) external returns (bytes32 messageId);

    /// @notice Gets the fee for a CCIP transfer
    /// @param _destinationChainSelector The selector of the destination chain
    /// @param _tokenAddress The address of the token being bridged
    /// @param _minAmountOut The minimum amount of weth the token will be swapped for on uniswap
    /// @param _wethAmount The amount of weth to be swapped for the token
    /// @param _data The data to be sent with the CCIP transfer
    /// @param _extraArgs Additional arguments for the fee calculation
    /// @return fee The fee for the CCIP transfer
    function getFee(
        uint64 _destinationChainSelector,
        address _tokenAddress,
        uint256 _minAmountOut,
        uint256 _deadline,
        uint256 _wethAmount,
        bytes memory _data,
        bytes memory _extraArgs
    ) external view returns (uint256);

    /// @notice Gets the fee token
    /// @return feeToken The address of the fee token
    function getFeeToken() external view returns (address);
}
