// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IHookVault
/// @notice Interface for vaults used by OpHook for option swaps, with integrated pricing and strategy.
interface IHookVault {
    // ============ STRUCTS ============

    struct StrikeConfig {
        uint16 strikeOffsetBps;
        bool isPut;
        uint40 duration;
    }

    // ============ EVENTS ============

    event MintAndDeliver(address indexed option, address indexed buyer, uint256 collateralUsed, uint256 optionsDelivered);
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

    // ============ HOOK INTERACTION ============

    function getQuote(address option, uint256 amount, bool cashForOption)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice);

    function mintAndDeliver(address option, uint256 amount, address buyer) external returns (uint256 delivered);

    function pairRedeem(address option, uint256 amount) external;

    function transferCash(address token, uint256 amount, address to) external;
}
