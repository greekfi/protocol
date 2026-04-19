// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract GasBreakdown is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Collateral public redemptionTemplate;
    Option public optionTemplate;
    Factory public factory;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        vm.createSelectFork(vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")), 43189435);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        redemptionTemplate = new Collateral("Short Template", "SHORT");
        optionTemplate = new Option("Long Template", "LONG");

        // Deploy Factory
        factory = new Factory(address(redemptionTemplate), address(optionTemplate));

        IERC20(address(stableToken)).approve(address(factory), type(uint256).max);
        IERC20(address(shakyToken)).approve(address(factory), type(uint256).max);
    }

    function test_GasBreakdown_Step1_Clone() public {
        uint256 gasBefore = gasleft();
        address redemption_ = Clones.clone(address(redemptionTemplate));
        uint256 gasClone1 = gasBefore - gasleft();
        console.log("Clone Collateral:", gasClone1);

        gasBefore = gasleft();
        address option_ = Clones.clone(address(optionTemplate));
        uint256 gasClone2 = gasBefore - gasleft();
        console.log("Clone Option:", gasClone2);

        console.log("Total Clone Cost:", gasClone1 + gasClone2);
    }

    function test_GasBreakdown_Step2_Init() public {
        address redemption_ = Clones.clone(address(redemptionTemplate));
        address option_ = Clones.clone(address(optionTemplate));

        Collateral redemption = Collateral(redemption_);
        Option option = Option(option_);

        uint256 gasBefore = gasleft();
        redemption.init(
            address(shakyToken),
            address(stableToken),
            uint40(block.timestamp + 30 days),
            1e18,
            false,
            false,
            address(0),
            option_,
            address(factory)
        );
        uint256 gasCollateralInit = gasBefore - gasleft();
        console.log("Collateral.init():", gasCollateralInit);

        gasBefore = gasleft();
        option.init(redemption_, msg.sender);
        uint256 gasOptionInit = gasBefore - gasleft();
        console.log("Option.init():", gasOptionInit);

        console.log("Total Init Cost:", gasCollateralInit + gasOptionInit);
    }

    function test_GasBreakdown_Step3_CreateOptionInfo() public {
        address redemption_ = Clones.clone(address(redemptionTemplate));
        address option_ = Clones.clone(address(optionTemplate));

        Collateral redemption = Collateral(redemption_);
        Option option = Option(option_);

        redemption.init(
            address(shakyToken),
            address(stableToken),
            uint40(block.timestamp + 30 days),
            1e18,
            false,
            false,
            address(0),
            option_,
            address(factory)
        );
        option.init(redemption_, msg.sender);

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
