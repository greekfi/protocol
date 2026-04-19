// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title ConstantsBase
/// @notice Contract addresses for Base chain (chain ID 8453)
library ConstantsBase {
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address public constant POOLMANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address public constant POSITIONDESCRIPTOR = 0x25D093633990DC94BeDEeD76C8F3CDaa75f3E7D5;
    address public constant POSITIONMANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address public constant QUOTER = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;
    address public constant STATEVIEW = 0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71;
    address public constant UNIVERSALROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Uniswap v3 WETH/USDC pool (0.05% fee tier) for TWAP price feed
    address public constant WETH_UNI_POOL = 0xd0b53D9277642d899DF5C87A3966A349A798F224;

    // Decimals
    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant USDC_DECIMALS = 6;

    // Time-related constants
    uint256 public constant SECONDS_PER_YEAR = 31536000;

    // Option pricing defaults
    uint256 public constant DEFAULT_VOLATILITY = 2e17; // 20% annualized, 1e18 scale
    uint256 public constant DEFAULT_RISK_FREE_RATE = 5e16; // 5% annualized, 1e18 scale

    // Uniswap V3 pool fee tiers
    uint24 public constant FEE_TIER_LOW = 500; // 0.05%
    uint24 public constant FEE_TIER_MEDIUM = 3000; // 0.3%
    uint24 public constant FEE_TIER_HIGH = 10000; // 1%
}
