// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IYieldVault
/// @notice Interface for the yield vault — ERC4626 + ERC-7540 async redeems + EIP-1271 Bebop signing.
interface IYieldVault {
    // ============ EVENTS ============

    event OptionWhitelisted(address indexed option, bool allowed);
    event OptionsBurned(address indexed option, uint256 amount);

    // ============ ERRORS ============

    error NotWhitelisted();
    error InsufficientIdle();
    error InvalidAddress();
    error ZeroAmount();
    error Unauthorized();
    error InsufficientClaimable();
    error WithdrawDisabled();
    error AsyncOnly();

    // ============ OPERATOR ============

    /// @notice Pair-redeem option + redemption tokens to recover collateral
    function burn(address option, uint256 amount) external;

    /// @notice Set the Bebop approval target (BalanceManager) for option token transfers
    function setBebopApprovalTarget(address target) external;

    // ============ ASYNC REDEEM (ERC-7540) ============

    /// @notice Fulfill a pending redeem request, snapshotting the asset value
    function fulfillRedeem(address controller) external;

    /// @notice Batch fulfill multiple pending redeem requests
    function fulfillRedeems(address[] calldata controllers) external;

    // ============ VIEW ============

    function idleCollateral() external view returns (uint256);
    function utilizationBps() external view returns (uint256);
    function totalCommitted() external view returns (uint256);
    function committed(address option) external view returns (uint256);
    function whitelistedOptions(address option) external view returns (bool);

    function getVaultStats()
        external
        view
        returns (
            uint256 totalAssets_,
            uint256 totalShares_,
            uint256 idle_,
            uint256 committed_,
            uint256 utilizationBps_
        );

    function getPositionInfo(address option)
        external
        view
        returns (uint256 committed_, uint256 redemptionBalance_, bool expired_);
}
