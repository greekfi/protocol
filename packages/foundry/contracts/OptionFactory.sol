// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenData, OptionInfo, OptionParameter } from "./OptionBase.sol";
import { AddressSet } from "./AddressSet.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Option } from "./Option.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Redemption } from "./Redemption.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

using SafeERC20 for IERC20;
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
    AddressSet public collaterals;
    AddressSet public considerations;
    AddressSet public optionsSet;

    constructor(address redemption_, address option_) Ownable(msg.sender) {
        redemptionClone = redemption_;
        optionClone = option_;
        collaterals = new AddressSet();
        considerations = new AddressSet();
        optionsSet = new AddressSet();
    }

    function createOption(
        string memory optionName,
        string memory redemptionName,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    ) public returns (address){
        address redemption_ = Clones.clone(redemptionClone);
        address option_ = Clones.clone(optionClone);

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(redemptionName, redemptionName, collateral, consideration, expirationDate, strike, isPut, option_);
        option.init(optionName, optionName, collateral, consideration, expirationDate, strike, isPut, redemption_, msg.sender);

//        redemption.setOption(option_);
//        option.setRedemption(redemption_);
//        option.transferOwnership(owner());

        OptionInfo memory info = OptionInfo(
            TokenData(option_, optionName, optionName, option.collDecimals),
            TokenData(redemption_, redemptionName, redemptionName, option.collDecimals),
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
        collaterals.add(collateral);
        considerations.add(consideration);
        optionsSet.add(option_);
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

    function get(address collateral, address consideration) public view returns (OptionInfo[] memory) {
        return options[collateral][consideration];
    }

    function getOptions() public view returns (address[] memory) {
        return optionsSet.values();
    }

    function getOptionsCount() public view returns (uint256) {
        return optionsSet.length();
    }

    function isOption(address option_) public view returns (bool) {
        return optionsSet.contains(option_);
    }

    function getCollaterals() public view returns (address[] memory) {
        return collaterals.values();
    }

    function getConsiderations() public view returns (address[] memory) {
        return considerations.values();
    }

    function getCollateralsCount() public view returns (uint256) {
        return collaterals.length();
    }

    function getConsiderationsCount() public view returns (uint256) {
        return considerations.length();
    }

    function isCollateral(address token) public view returns (bool) {
        return collaterals.contains(token);
    }

    function isConsideration(address token) public view returns (bool) {
        return considerations.contains(token);
    }
}
