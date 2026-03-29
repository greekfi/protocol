// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IERC7540Redeem
/// @notice Async redeem interface per ERC-7540
/// @dev Vaults implementing this MUST override ERC-4626 redeem/withdraw as claim functions.
///      withdraw MUST revert. maxWithdraw MUST return 0. maxRedeem returns claimable shares.
interface IERC7540Redeem {
    /// @notice Emitted when a redeem request is submitted
    /// @param controller The address that controls this request and can claim
    /// @param owner The address whose shares are locked
    /// @param requestId The request identifier (0 for single-request-per-controller vaults)
    /// @param sender The address that initiated the request
    /// @param shares The number of shares locked
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /// @notice Submit a request to redeem shares asynchronously
    /// @param shares Number of shares to redeem
    /// @param controller Address that will control the claim
    /// @param owner Address whose shares are locked
    /// @return requestId The request identifier
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /// @notice Returns pending (not yet fulfilled) shares for a controller
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 pendingShares);

    /// @notice Returns claimable (fulfilled, ready to claim) shares for a controller
    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);
}

/// @title IERC7540Operator
/// @notice Operator authorization for ERC-7540 vaults
interface IERC7540Operator {
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /// @notice Authorize or revoke an operator for the caller
    function setOperator(address operator, bool approved) external returns (bool);

    /// @notice Check if an address is an authorized operator for a controller
    function isOperator(address controller, address operator) external view returns (bool);
}
