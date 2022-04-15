pragma solidity 0.8.11;

import "../interfaces/AggregatorV3Interface.sol";

contract ChainlinkPriceFetcher {
  function getChainlinkPrice(AggregatorV3Interface chainlinkFeed) external view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound,
      uint256 blockTimestamp
    )
  {
    (roundId, answer, startedAt, updatedAt, answeredInRound) = chainlinkFeed.latestRoundData();
    blockTimestamp = block.timestamp;
  }
}
