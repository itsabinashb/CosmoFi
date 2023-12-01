// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import 'chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

abstract contract PriceFeed {
  AggregatorV3Interface public aggregator;

  function setAggregatorAddress(AggregatorV3Interface _aggregator) internal {
    aggregator = AggregatorV3Interface(_aggregator);
  }

  function getPrice() internal view returns (int) {
    
    (
            /* uint80 roundID */,
            int answer,             // What is the decimal of returned value? Is it 18? See Code walk note to understand better ⭐️
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = aggregator.latestRoundData();
    return answer;  // I might need to devide it by 1e18
  }
}
