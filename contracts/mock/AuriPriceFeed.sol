pragma solidity 0.8.11;

contract AuriPriceFeed {
  event RoundDataSync(
    uint80 indexed roundId,
    int256 indexed answer,
    uint256 indexed updatedAt
  );

  struct Data{
    uint80 roundId;
    int256 answer;
    uint256 updatedAt;
  }

  Data public data;
  uint8 public constant decimals = 8;
  string public description;
  address public immutable chainlinkFeedOnEth; // only for reference, not to be used

  constructor(
    string memory _description,
    address _chainlinkFeedOnEth
  ) {
    description = _description;
    chainlinkFeedOnEth = _chainlinkFeedOnEth;
  }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    answer = data.answer;
    updatedAt = data.updatedAt;
    // only provide data to save gas
    roundId = 0;
    startedAt = 0;
    answeredInRound = 0;
  }

  function setRoundData(
    uint80 roundId,
    int256 answer
  ) external {
    require(answer > 0, "bad answer");
    // the incoming data is newer than the current data
    if (data.roundId < roundId) {
      data.roundId = roundId;
      data.answer = answer;
    }

    data.updatedAt = block.timestamp;

    // have to use the data from storage, not data from the function
    emit RoundDataSync(
      data.roundId,
      data.answer,
      data.updatedAt
    );
  }
}