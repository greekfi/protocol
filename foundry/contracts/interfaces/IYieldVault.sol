// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IYieldVault
/// @notice Interface for strategy vaults that combine LP deposits, option pricing, and strategy.
///         The OpHook programs against this interface.
interface IYieldVault {
    // ============ STRUCTS ============

    /// @notice Defines an option strike to auto-create on roll
    /// @param strikeOffsetBps Strike relative to spot (10000 = ATM, 11000 = 10% OTM call, 9000 = 10% ITM)
    /// @param isPut True for put, false for call
    /// @param duration Seconds until expiry for newly created options
    struct StrikeConfig {
        uint16 strikeOffsetBps;
        bool isPut;
        uint40 duration;
    }

    // ============ EVENTS ============

    event MintAndDeliver(
        address indexed option, address indexed buyer, uint256 collateralUsed, uint256 optionsDelivered
    );
    event PairRedeemed(address indexed option, uint256 amount);
    event SettlementReconciled(address indexed option, uint256 settled);
    event ConsiderationSwapped(address indexed token, uint256 considerationIn, uint256 collateralOut);
    event HookUpdated(address indexed hook, bool authorized);
    event OptionWhitelisted(address indexed option, bool allowed);
    event MaxCommitmentUpdated(uint256 oldBps, uint256 newBps);
    event OptionsRolled(address indexed expiredOption, address[] newOptions, address indexed caller, uint256 bounty);
    event StrategyUpdated();
    event VolatilityUpdated(uint256 oldVol, uint256 newVol);
    event RiskFreeRateUpdated(uint256 oldRate, uint256 newRate);
    event RollBountyUpdated(uint256 oldBounty, uint256 newBounty);
    event SpreadUpdated(uint256 oldSpread, uint256 newSpread);
    event SkewUpdated(int256 oldSkew, int256 newSkew);
    event KurtosisUpdated(int256 oldKurtosis, int256 newKurtosis);
    event OptionsBurned(address indexed option, uint256 amount);

    // ============ ERRORS ============

    error OnlyHook();
    error NotWhitelisted();
    error ExceedsCommitmentCap();
    error InsufficientIdle();
    error NothingToSettle();
    error NoConsiderationToSwap();
    error SwapFailed();
    error NoGainFromSwap();
    error InvalidBps();
    error InvalidAddress();
    error ZeroAmount();
    error OptionNotExpired();
    error AlreadyRolled();
    error CollateralMismatch();
    error InsufficientCash();
    error NoStrategyConfigured();
    error Unauthorized();
    error InsufficientClaimable();
    error WithdrawDisabled();
    error AsyncOnly();
    error BebopNotConfigured();

    // ============ OPERATOR ============

    /// @notice Pair-redeem option + redemption tokens to recover collateral
    function burn(address option, uint256 amount) external;

    /// @notice Set the Bebop approval target (BalanceManager) for option token transfers
    function setBebopApprovalTarget(address target) external;

    // ============ ASYNC REDEEM (ERC-7540) ============

    /// @notice Fulfill a pending redeem request, snapshotting the asset value
    /// @param controller The controller whose request to fulfill
    function fulfillRedeem(address controller) external;

    /// @notice Batch fulfill multiple pending redeem requests
    function fulfillRedeems(address[] calldata controllers) external;

    // ============ HOOK INTERACTION ============

    /// @notice Get a price quote for an option swap
    /// @param option Option contract address
    /// @param amount Input amount (cash if cashForOption=true, options if false)
    /// @param cashForOption True = buying options with cash, false = selling options for cash
    /// @return outputAmount Amount of output tokens
    /// @return unitPrice Price per option in cash-token units
    function getQuote(address option, uint256 amount, bool cashForOption)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice);

    /// @notice Mint options using vault collateral and deliver to buyer
    /// @param option Option contract address (must be whitelisted)
    /// @param amount Collateral amount to commit
    /// @param buyer Recipient of the Option tokens
    /// @return delivered Number of Option tokens delivered
    function mintAndDeliver(address option, uint256 amount, address buyer) external returns (uint256 delivered);

    /// @notice Pair-redeem matched Option + Redemption tokens
    /// @param option Option contract address
    /// @param amount Number of option tokens to pair-redeem
    function pairRedeem(address option, uint256 amount) external;

    /// @notice Transfer cash tokens from vault to a recipient (for buyback settlements)
    /// @param token Cash token address
    /// @param amount Amount to transfer
    /// @param to Recipient
    function transferCash(address token, uint256 amount, address to) external;

    // ============ PERMISSIONLESS ============

    /// @notice Roll expired options into new ones per strategy config. First caller gets bounty.
    /// @param expiredOption The expired option to roll from
    /// @return newOptions Array of newly created option addresses
    function rollOptions(address expiredOption) external returns (address[] memory newOptions);

    /// @notice Reconcile bookkeeping after sweep() on the Redemption contract
    /// @param option Option whose Redemption was swept
    function handleSettlement(address option) external;

    // ============ VIEW ============

    function getCollateralPrice() external view returns (uint256);
    function cashToken() external view returns (address);
    function volatility() external view returns (uint256);
    function riskFreeRate() external view returns (uint256);
    function idleCollateral() external view returns (uint256);
    function utilizationBps() external view returns (uint256);
    function totalCommitted() external view returns (uint256);
    function committed(address option) external view returns (uint256);
    function whitelistedOptions(address option) external view returns (bool);
    function authorizedHooks(address hook) external view returns (bool);
    function rollBounty() external view returns (uint256);
    function spreadBps() external view returns (uint256);
    function skew() external view returns (int256);
    function kurtosis() external view returns (int256);

    function getVaultStats()
        external
        view
        returns (
            uint256 totalAssets_,
            uint256 totalShares_,
            uint256 idle_,
            uint256 committed_,
            uint256 utilizationBps_,
            uint256 totalPremiums_
        );

    function getPositionInfo(address option)
        external
        view
        returns (uint256 committed_, uint256 redemptionBalance_, bool expired_);
}
