// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Option } from "./Option.sol";
import { Redemption, TokenData, OptionInfo, OptionParameter  } from "./Redemption.sol";

using SafeERC20 for ERC20;

interface IPermit2 {
    function transferFrom(address from, address to, uint160 amount, address token) external;

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);
}

// The Long OptionParameter contract is the owner of the Short OptionParameter contract
// The Long OptionParameter contract is the only one that can mint new mint
// The Long OptionParameter contract is the only one that can exercise mint
// The redemption is only possible if you own both the Long and Short OptionParameter contracts but
// performed by the Long OptionParameter contract

// In mint traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

contract OptionFactory is Ownable {
    address public redemptionClone;
    address public optionClone;
    uint64 public fee;
    IPermit2 public permit2;

    uint256 constant MAX_FEE = 0.01e18; // 1%

    error BlocklistedToken();
    error InvalidAddress();

    event OptionCreated(
        address option,
        address redemption,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    );

    event TokenBlocked(address token, bool blocked);

    mapping(address => mapping(address => OptionInfo[])) public options;

    // Collaterals tracking
    address[] private _collaterals;
    mapping(address => bool) private _collateralsSet;

    // Considerations tracking
    address[] private _considerations;
    mapping(address => bool) private _considerationsSet;

    // Options tracking
    address[] private _optionsSet;
    mapping(address => bool) private _optionsMap;

    // Redemptions tracking
    address[] private _redemptionsSet;
    mapping(address => bool) private _redemptionsMap;

    // Blocklist for fee-on-transfer and rebasing tokens
    mapping(address => bool) public blocklist;

    constructor(address redemption_, address option_, address permit2_, uint64 fee_) Ownable(msg.sender) {
        require(fee_ <= MAX_FEE, "fee too high");
        redemptionClone = redemption_;
        optionClone = option_;
        permit2 = IPermit2(permit2_);
        fee = fee_;
    }

    function createOption(
        string memory optionName,
        string memory redemptionName,
        address collateral,
        address consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut
    ) public returns (address) {
        // Check blocklist for fee-on-transfer and rebasing tokens
        if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();

        address redemption_ = Clones.clone(redemptionClone);
        address option_ = Clones.clone(optionClone);

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(
            collateral,
            consideration,
            expirationDate,
            strike,
            isPut,
            option_,
            address(this),
            fee
        );
        option.init(redemption_, msg.sender, fee);

        OptionInfo memory info = OptionInfo(
            TokenData(option_, optionName, optionName, option.decimals()),
            TokenData(redemption_, redemptionName, redemptionName, redemption.decimals()),
            TokenData(collateral, option.name(), option.symbol(), option.decimals()),
            TokenData(
                consideration,
                redemption.considerationData().name,
                redemption.considerationData().symbol,
                redemption.considerationData().decimals
            ),
            OptionParameter(optionName, redemptionName, collateral, consideration, expirationDate, strike, isPut),
            collateral,
            consideration,
            expirationDate,
            strike,
            isPut
        );

        options[collateral][consideration].push(info);

        // Add collateral if not already tracked
        if (!_collateralsSet[collateral]) {
            _collateralsSet[collateral] = true;
            _collaterals.push(collateral);
        }

        // Add consideration if not already tracked
        if (!_considerationsSet[consideration]) {
            _considerationsSet[consideration] = true;
            _considerations.push(consideration);
        }

        // Add option if not already tracked
        if (!_optionsMap[option_]) {
            _optionsMap[option_] = true;
            _optionsSet.push(option_);
        }

        // Add redemption if not already tracked
        if (!_redemptionsMap[redemption_]) {
            _redemptionsMap[redemption_] = true;
            _redemptionsSet.push(redemption_);
        }

        ERC20(collateral).approve(owner(), type(uint256).max);
        emit OptionCreated(option_, redemption_, collateral, consideration, expirationDate, strike, isPut);
        return option_;
    }

    function createOptions(OptionParameter[] memory optionParams) public {
        for (uint256 i = 0; i < optionParams.length; i++) {
            OptionParameter memory param = optionParams[i];
            createOption(
                param.optionSymbol,
                param.redemptionSymbol,
                param.collateral_,
                param.consideration_,
                param.expiration,
                param.strike,
                param.isPut
            );
        }
    }

    /**
     * @notice External function to transfer tokens using Permit2 or ERC20 allowance
     * @dev Only called by redemption contracts. Tries Permit2 first (modern UX), falls back to ERC20
     */
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success) {
        // Only redemption contracts can call this (used in mint() and exercise())
        if (!_redemptionsMap[msg.sender]) revert InvalidAddress();

        // Try Permit2 first (gasless approvals, modern UX)
        // (uint160 allowAmount, uint48 expiration,) = permit2.allowance(from, token, address(this));

        // if (allowAmount >= amount && expiration > uint48(block.timestamp)) {
        //     permit2.transferFrom(from, to, amount, token);
        //     return true;
        // }

        // Fallback to standard ERC20 allowance (will revert if insufficient)
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    function get(address collateral, address consideration) public view returns (OptionInfo[] memory) {
        return options[collateral][consideration];
    }

    function getOptions() public view returns (address[] memory) {
        return _optionsSet;
    }

    function getOptionsCount() public view returns (uint256) {
        return _optionsSet.length;
    }

    function isOption(address option_) public view returns (bool) {
        return _optionsMap[option_];
    }

    function getCollaterals() public view returns (address[] memory) {
        return _collaterals;
    }

    function getConsiderations() public view returns (address[] memory) {
        return _considerations;
    }

    function getCollateralsCount() public view returns (uint256) {
        return _collaterals.length;
    }

    function getConsiderationsCount() public view returns (uint256) {
        return _considerations.length;
    }

    function isCollateral(address token) public view returns (bool) {
        return _collateralsSet[token];
    }

    function isConsideration(address token) public view returns (bool) {
        return _considerationsSet[token];
    }

    /// @notice Add a token to the blocklist (e.g., fee-on-transfer or rebasing tokens)
    /// @param token The token address to blocklist
    function addToBlocklist(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /// @notice Remove a token from the blocklist
    /// @param token The token address to remove from blocklist
    function removeFromBlocklist(address token) external onlyOwner {
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /// @notice Check if a token is blocklisted
    /// @param token The token address to check
    /// @return bool True if the token is blocklisted
    function isBlocklisted(address token) external view returns (bool) {
        return blocklist[token];
    }
}
