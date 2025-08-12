//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Useful for debugging. Remove when deploying to a live network.
import "forge-std/console.sol";

// Use openzeppelin to inherit battle-tested implementations (ERC20, ERC721, etc)
// import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Simple Pricing Oracle
 * @author lababidi
 */
contract OptionPriceOracle {
    // State Variables
    address public immutable owner;

	mapping(uint256=>mapping(uint256=>uint256)) public price;

    // Events: a way to emit log statements from smart contract that can be listened to by external parties
//    event GreetingChange(address indexed greetingSetter, string newGreeting, bool premium, uint256 value);

    // Constructor: Called once on contract deployment
    // Check packages/foundry/deploy/Deploy.s.sol
    constructor(address _owner) {
        owner = _owner;
    }

    // Modifier: used to define a set of rules that must be met before or after a function is executed
    // Check the withdraw() function
    modifier isOwner() {
        // msg.sender: predefined variable that represents address of the account that called the current function
        require(msg.sender == owner, "Not the Owner");
        _;
    }

	function setPrice(uint256 strike, uint256 date, uint256 _price) public  {
		price[strike][date] = _price;
	}

	function getPrice(uint256 strike, uint256 date) public view returns (uint256){
		return price[strike][date];
	}

//	function getCalcPrice() public  returns (uint256) {
//		return price;
//	}

}
