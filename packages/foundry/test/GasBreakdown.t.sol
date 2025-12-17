// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";
import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract GasBreakdown is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionTemplate;
    Option public optionTemplate;
    OptionFactory public factory;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    string public constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";

    function setUp() public {
        vm.createSelectFork(UNICHAIN_RPC_URL);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        redemptionTemplate = new Redemption(
            "Short Template", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 1e18, false
        );

        optionTemplate = new Option("Long Template", "LONG", address(redemptionTemplate));

        factory = new OptionFactory(address(redemptionTemplate), address(optionTemplate), 0.0001e18);

        IERC20(address(stableToken)).approve(address(factory), type(uint256).max);
        IERC20(address(shakyToken)).approve(address(factory), type(uint256).max);
    }

    function test_GasBreakdown_Step1_Clone() public {
        uint256 gasBefore = gasleft();
        address redemption_ = Clones.clone(address(redemptionTemplate));
        uint256 gasClone1 = gasBefore - gasleft();
        console.log("Clone Redemption:", gasClone1);

        gasBefore = gasleft();
        address option_ = Clones.clone(address(optionTemplate));
        uint256 gasClone2 = gasBefore - gasleft();
        console.log("Clone Option:", gasClone2);

        console.log("Total Clone Cost:", gasClone1 + gasClone2);
    }

    function test_GasBreakdown_Step2_Init() public {
        address redemption_ = Clones.clone(address(redemptionTemplate));
        address option_ = Clones.clone(address(optionTemplate));

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        uint256 gasBefore = gasleft();
        redemption.init(
            address(shakyToken),
            address(stableToken),
            uint40(block.timestamp + 30 days),
            1e18,
            false,
            option_,
            address(factory),
            0.0001e18
        );
        uint256 gasRedemptionInit = gasBefore - gasleft();
        console.log("Redemption.init():", gasRedemptionInit);

        gasBefore = gasleft();
        option.init(redemption_, msg.sender, 0.0001e18);
        uint256 gasOptionInit = gasBefore - gasleft();
        console.log("Option.init():", gasOptionInit);

        console.log("Total Init Cost:", gasRedemptionInit + gasOptionInit);
    }

    function test_GasBreakdown_Step3_CreateOptionInfo() public {
        address redemption_ = Clones.clone(address(redemptionTemplate));
        address option_ = Clones.clone(address(optionTemplate));

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(
            address(shakyToken),
            address(stableToken),
            uint40(block.timestamp + 30 days),
            1e18,
            false,
            option_,
            address(factory),
            0.0001e18
        );
        option.init(redemption_, msg.sender, 0.0001e18);

        uint256 gasBefore = gasleft();

        // This is what createOption does - multiple external calls
        uint8 optionDecimals = option.decimals();
        console.log("  option.decimals():", gasBefore - gasleft());

        gasBefore = gasleft();
        uint8 redemptionDecimals = redemption.decimals();
        console.log("  redemption.decimals():", gasBefore - gasleft());

        gasBefore = gasleft();
        string memory optionName = option.name();
        console.log("  option.name():", gasBefore - gasleft());

        gasBefore = gasleft();
        string memory optionSymbol = option.symbol();
        console.log("  option.symbol():", gasBefore - gasleft());

        gasBefore = gasleft();
        redemption.considerationData();
        console.log("  redemption.considerationData():", gasBefore - gasleft());
    }

    function test_GasBreakdown_Step4_StorageOperations() public {
        address redemption_ = Clones.clone(address(redemptionTemplate));
        address option_ = Clones.clone(address(optionTemplate));

        // Simulate the tracking operations
        uint256 gasBefore = gasleft();

        // Simulate first collateral push
        address[] memory tempArray = new address[](0);
        tempArray = new address[](1);
        tempArray[0] = address(shakyToken);

        uint256 gasArrayPush = gasBefore - gasleft();
        console.log("Array push (first):", gasArrayPush);

        gasBefore = gasleft();
        // Simulate mapping write
        bool tempBool = true;
        uint256 gasMappingWrite = gasBefore - gasleft();
        console.log("Mapping write:", gasMappingWrite);
    }

    function test_GasBreakdown_Full() public {
        uint256 gasBefore = gasleft();

        address optionAddress = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 60 days), 2e18, false
        );

        uint256 totalGas = gasBefore - gasleft();
        console.log("\n=== FULL createOption() GAS ===");
        console.log("Total:", totalGas);
    }
}
