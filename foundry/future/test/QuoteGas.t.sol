// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/NuAMMv2.sol";
import "../contracts/mocks/MockERC20.sol";

contract QuoteGasTest is Test {
    NuAMMv2 public book;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    function setUp() public {
        book = new NuAMMv2();
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);

        tokenB.mint(address(this), 100e18);
        tokenB.approve(address(book), type(uint256).max);
        book.deposit(address(tokenB), 10e18);
    }

    function test_single_cold_quote() public {
        book.quote(address(tokenB), address(tokenA), int24(1000), 10e18, false);
    }

    function test_single_warm_quote() public {
        // Warm everything up
        book.quote(address(tokenB), address(tokenA), int24(1000), 5e18, false);
        book.cancel(address(tokenB), address(tokenA), int24(1000), false);

        // Now measure warm
        book.quote(address(tokenB), address(tokenA), int24(1000), 5e18, false);
    }

    function test_warm_requote() public {
        book.quote(address(tokenB), address(tokenA), int24(1000), 5e18, false);
        book.requote(address(tokenB), address(tokenA), int24(1000), int24(2000), 5e18, false);
        book.requote(address(tokenB), address(tokenA), int24(2000), int24(1000), 5e18, false);

        // Fully warm
        book.requote(address(tokenB), address(tokenA), int24(1000), int24(2000), 5e18, false);
    }
}
