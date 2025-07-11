// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

import { TokenData } from "./OptionBase.sol";
import { ShortOption } from "./ShortOption.sol";
import { LongOption } from "./LongOption.sol";

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

struct Option {
    address longOption;
    address shortOption;
    string longSymbol;
    string shortSymbol;
    string collateralName;
    string considerationName;
    string collateralSymbol;
    string considerationSymbol;
    uint8 collateralDecimals;
    uint8 considerationDecimals;
    address collateral;
    address consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

struct OptionParameter {
    string longSymbol;
    string shortSymbol;
    address collateral;
    address consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

struct OptionPair {
    address collateral;
    address consideration;
    string collateralName;
    string considerationName;
    uint8 collateralDecimals;
    uint8 considerationDecimals;
    string collateralSymbol;
    string considerationSymbol;
}

contract OptionFactory is Ownable {
    address public shortContract;
    address public longContract;

    event OptionCreated(
        address longOption,
        address shortOption,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    );

    address[] public createdOptions;
    OptionPair[] public pairs;
    AddressSet.Set public collaterals;
    AddressSet.Set public considerations;
    mapping(string => OptionPair) public pairMap;
    mapping(uint256 => address[]) public shortLong;

    mapping(address => mapping(address => Option[])) public pairToOption;

    mapping(address => mapping(uint256 => mapping(uint256 => address[]))) public allOptions;

    constructor(address short_, address long_) Ownable(msg.sender) {
        shortContract = short_;
        longContract = long_;
    }


    function createOption(
        string memory longSymbol,
        string memory shortSymbol,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    ) public {
        address short = Clones.clone(shortContract);
        address long = Clones.clone(longContract);

        ShortOption shortOption = ShortOption(short);
        LongOption longOption = LongOption(long);

        shortOption.init(shortSymbol, shortSymbol, collateral, consideration, expirationDate, strike, isPut);
        longOption.init(longSymbol, longSymbol, collateral, consideration, expirationDate, strike, isPut);

        shortOption.setLongOption(long);
        longOption.setShortOption(short);
        shortOption.transferOwnership(long);
        longOption.transferOwnership(owner());

        string memory pair_name = string(abi.encodePacked(collateral, "_", consideration));
        Option memory option = Option(long, short, longSymbol, shortSymbol, longOption.collateralData().name, shortOption.considerationData().name, longOption.collateralData().symbol, shortOption.considerationData().symbol, longOption.collateralData().decimals, shortOption.considerationData().decimals, collateral, consideration, expirationDate, strike, isPut);

        OptionPair memory pair = OptionPair(
            collateral, consideration, 
            option.collateralName, option.considerationName, 
            option.collateralDecimals, option.considerationDecimals, 
            option.collateralSymbol, option.considerationSymbol);
        if (pairMap[pair_name].collateral == address(0)) {
            pairs.push(pair);
            pairMap[pair_name] = pair;
        }
        createdOptions.push(long);
        allOptions[collateral][expirationDate][strike].push(long);
        pairToOption[collateral][consideration].push(option);
        collaterals.add(collateral);
        considerations.add(consideration);
        emit OptionCreated(long, short, collateral, consideration, expirationDate, strike, isPut);
    }


    function createOptions(OptionParameter[] memory options) public {
        for(uint256 i = 0; i < options.length; i++) {
            OptionParameter memory option = options[i];
            createOption(
                option.longSymbol, 
                option.shortSymbol, 
                option.collateral, 
                option.consideration, 
                option.expiration, 
                option.strike, 
                option.isPut
                );
        }
    }

    function getCreatedOptions() public view returns (address[] memory) {
        return createdOptions;
    }

    function getPairs() public view returns (OptionPair[] memory) {
        return pairs;
    }

    function getPairToOptions(address collateral, address consideration) public view returns (Option[] memory) {
        return pairToOption[collateral][consideration];
    }

}
