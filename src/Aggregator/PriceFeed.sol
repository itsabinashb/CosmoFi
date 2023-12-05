// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import 'chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

abstract contract PriceFeed {
  AggregatorV3Interface public aggregatorBTC;
  AggregatorV3Interface public aggregatorDAI;

  function setAggregatorAddressForBTC(AggregatorV3Interface _aggregator) internal {
    aggregatorBTC = AggregatorV3Interface(_aggregator);
  }

  function setAggregatorAddressForDAI(AggregatorV3Interface _aggregator) internal {
    aggregatorDAI = AggregatorV3Interface(_aggregator);
  }

  function getPriceForBTC() internal view returns (int) {
    
    (
            /* uint80 roundID */,
            int answer,             // What is the decimal of returned value? Is it 18? See Code walk note to understand better ⭐️
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = aggregatorBTC.latestRoundData();
    return answer;  // I might need to devide it by 1e18
  }

  function getPriceForDAI() internal view returns (int) {
    
    (
            /* uint80 roundID */,
            int answer,             // What is the decimal of returned value? Is it 18? See Code walk note to understand better ⭐️
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = aggregatorDAI.latestRoundData();
    return answer;  // I might need to devide it by 1e18
  }


}
