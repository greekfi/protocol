// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IOptionVault {
    // ============ EVENTS ============

    event OptionWhitelisted(address indexed option, bool allowed);
    event MintAndDeliver(address indexed option, address indexed buyer, uint256 collateralUsed, uint256 optionsDelivered);
    event PairRedeemed(address indexed option, uint256 amount);
    event SettlementReconciled(address indexed option, uint256 settled);
    event PremiumReceived(address indexed token, uint256 amount);
    event ConsiderationSwapped(address indexed token, uint256 considerationIn, uint256 collateralOut);
    event HookUpdated(address indexed oldHook, address indexed newHook);
    event MaxCommitmentUpdated(uint256 oldBps, uint256 newBps);

    // ============ ERRORS ============

    error OnlyHook();
    error NotWhitelisted();
    error ExceedsCommitmentCap();
    error InsufficientIdle();
    error NothingToSettle();
    error NoConsiderationToSwap();
    error SwapFailed();
    error InvalidBps();

    // ============ CORE FUNCTIONS ============

    function mintAndDeliver(address option, uint256 amount, address buyer) external returns (uint256 optionsDelivered);
    function pairRedeem(address option, uint256 amount) external;
    function handleSettlement(address option) external;
    function receivePremium(address token, uint256 amount) external;
    function swapToCollateral(address considerationToken, address router, bytes calldata swapData) external;

    // ============ ADMIN FUNCTIONS ============

    function whitelistOption(address option, bool allowed) external;
    function setMaxCommitmentBps(uint256 bps) external;
    function setHook(address newHook) external;
    function setupFactoryApproval() external;

    // ============ VIEW FUNCTIONS ============

    function hook() external view returns (address);
    function totalCommitted() external view returns (uint256);
    function committed(address option) external view returns (uint256);
    function whitelistedOptions(address option) external view returns (bool);
    function maxCommitmentBps() external view returns (uint256);
    function idleCollateral() external view returns (uint256);
    function utilizationBps() external view returns (uint256);
    function totalPremiumsCollected() external view returns (uint256);
}
