// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ShakyToken is ERC20, Ownable {
    constructor() ERC20("ShakyToken", "SHK") Ownable(msg.sender) {
        // Mint initial supply to the contract deployer
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}


contract StableToken is ERC20, Ownable {
	constructor() ERC20("StableToken", "STK") Ownable(msg.sender) {
		// Mint initial supply to the contract deployer
		_mint(msg.sender, 1000000 * 10 ** decimals());
	}

	function mint(address to, uint256 amount) public onlyOwner {
		_mint(to, amount);
	}

	function burn(uint256 amount) public {
		_burn(msg.sender, amount);
	}
}
