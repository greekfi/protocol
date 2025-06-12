// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit2 } from "./interfaces/IPermit2.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

import { ShortOption } from "./ShortOption.sol";
import { LongOption } from "./LongOption.sol";

using SafeERC20 for IERC20;
// The Long Option contract is the owner of the Short Option contract
// The Long Option contract is the only one that can mint new mint
// The Long Option contract is the only one that can exercise mint
// The redemption is only possible if you own both the Long and Short Option contracts but
// performed by the Long Option contract

// In mint traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

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
    mapping(uint256 => address[]) public shortLong;

    mapping(address => mapping(uint256 => mapping(uint256 => address[]))) public allOptions;

    constructor(address short_, address long_) Ownable(msg.sender) {
        shortContract = short_;
        longContract = long_;
    }

    function createOption(
        string memory longOptionName,
        string memory shortOptionName,
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

        shortOption.init(shortOptionName, shortSymbol, collateral, consideration, expirationDate, strike, isPut);

        longOption.init(longOptionName, longSymbol, collateral, consideration, expirationDate, strike, isPut);

        createdOptions.push(long);
        allOptions[collateral][expirationDate][strike].push(long);
        shortOption.setLongOption(long);
        shortOption.transferOwnership(long);
        longOption.transferOwnership(owner());

        emit OptionCreated(long, short, collateral, consideration, expirationDate, strike, isPut);
    }

    function getCreatedOptions() public view returns (address[] memory) {
        return createdOptions;
    }
    // function getOption(address collateral, uint256 expiration, uint256 strike) public view returns (address[] memory) {
    //     return allOptions[collateral][expiration][strike];
    // }
}
