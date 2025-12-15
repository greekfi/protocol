// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenData, OptionInfo, OptionParameter } from "./OptionBase.sol";
import { AddressSet } from "./AddressSet.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Option } from "./Option.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Redemption } from "./Redemption.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

using SafeERC20 for ERC20;
using AddressSet for AddressSet.Set;

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
    uint256 public fee;
    IPermit2 public permit2;

    event OptionCreated(
        address option,
        address redemption,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    );

    mapping(address => mapping(address => OptionInfo[])) public options;
    AddressSet.Set private _collaterals;
    AddressSet.Set private _considerations;
    AddressSet.Set private _optionsSet;
    AddressSet.Set private _redemptionsSet;

    constructor(address redemption_, address option_, address permit2_, uint256 fee_) Ownable(msg.sender) {
        require(fee <= 0.01e18, "fee too high");
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
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    ) public returns (address) {
        address redemption_ = Clones.clone(redemptionClone);
        address option_ = Clones.clone(optionClone);

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(
            redemptionName,
            redemptionName,
            collateral,
            consideration,
            expirationDate,
            strike,
            isPut,
            option_,
            address(this),
            fee
        );
        option.init(
            optionName,
            optionName,
            collateral,
            consideration,
            expirationDate,
            strike,
            isPut,
            redemption_,
            msg.sender,
            address(this),
            fee
        );

        OptionInfo memory info = OptionInfo(
            TokenData(option_, optionName, optionName, option.decimals()),
            TokenData(redemption_, redemptionName, redemptionName, redemption.decimals()),
            TokenData(
                collateral,
                option.collateralData().name,
                option.collateralData().symbol,
                option.collateralData().decimals
            ),
            TokenData(
                consideration,
                option.considerationData().name,
                option.considerationData().symbol,
                option.considerationData().decimals
            ),
            OptionParameter(optionName, redemptionName, collateral, consideration, expirationDate, strike, isPut),
            collateral,
            consideration,
            expirationDate,
            strike,
            isPut
        );

        options[collateral][consideration].push(info);
        _collaterals.add(collateral);
        _considerations.add(consideration);
        _optionsSet.add(option_);
        _redemptionsSet.add(redemption_);
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
     * @dev Only called by option contracts to transfer tokens with stored allowances
     */
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success) {
        require(
            _redemptionsSet.contains(msg.sender) || _optionsSet.contains(msg.sender),
            "Not an option-redemption contract"
        );

        (uint160 allowAmount, uint48 expiration,) = permit2.allowance(from, token, address(this));

        if (allowAmount >= amount && expiration > uint48(block.timestamp)) {
            permit2.transferFrom(from, to, amount, token);
            return true;
        } else if (ERC20(token).allowance(from, address(this)) >= amount) {
            ERC20(token).safeTransferFrom(from, to, amount);
            return true;
        } else {
            require(false, "Insufficient allowance");
        }
    }

    function get(address collateral, address consideration) public view returns (OptionInfo[] memory) {
        return options[collateral][consideration];
    }

    function getOptions() public view returns (address[] memory) {
        return _optionsSet.values();
    }

    function getOptionsCount() public view returns (uint256) {
        return _optionsSet.length();
    }

    function isOption(address option_) public view returns (bool) {
        return _optionsSet.contains(option_);
    }

    function getCollaterals() public view returns (address[] memory) {
        return _collaterals.values();
    }

    function getConsiderations() public view returns (address[] memory) {
        return _considerations.values();
    }

    function getCollateralsCount() public view returns (uint256) {
        return _collaterals.length();
    }

    function getConsiderationsCount() public view returns (uint256) {
        return _considerations.length();
    }

    function isCollateral(address token) public view returns (bool) {
        return _collaterals.contains(token);
    }

    function isConsideration(address token) public view returns (bool) {
        return _considerations.contains(token);
    }
}
