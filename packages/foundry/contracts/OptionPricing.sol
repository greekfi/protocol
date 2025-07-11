// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
        
    function decimals() external view returns (uint8);
}

contract OptionPricing {
    function getPrice(address feed) external view returns (int256 price, uint8 decimals) {
        AggregatorV3Interface oracle = AggregatorV3Interface(feed);
        (, price, , ,) = oracle.latestRoundData();
        decimals = oracle.decimals();
    }
}