pragma solidity 0.8.11;

import "./interfaces/PriceOracle.sol";
import "./BoringOwnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./AuriMathLib.sol";

/*
  Before chainlink is available on Aurora, Aurigami will host its own price feeds by running 3 bot
  independently, forking price from chainlink on Eth mainnet and update it onto this contract.

  How it works:
  1. Liquidator bots (updator1, updatetor2, updator3) forks chainlink's price feed from eth mainnet (ignoring roundId and updatedAt)
  2. Liquidator bots sends its collected price through a transaction "updateMainFeedData", the updatedAt is set to block.timestamp
  3. During the transaction, the contract will consider the latest updates from 3 bots
    3.1. Update from a bot is considered invalid if (block.timestamp - updatedAt) > validPeriod (= 5 minutes by default)
    3.2. If the number of valid updates <= 1, does nothing
    3.3. If the number of valid updates >= 2, return the average of 2 closest prices, .i.e, (x+y)/2 with minimum (x-y) among prices[]. And updatedAt is set to min of participating answers.

  Why 3.3:
    1. A price is considered valid only if its updated in less than 5 minutes before the transaction
    2. A price is considered trustworthy if another updator also has an answer close to it

  How a query works:
    1. The Oracle checks for the latest mainFeedAnswers (calculated from updates above), if its not outdated, return the price
    2. If mainFeeds answer is outdated, return the backupFeed's price (a third-party's feed)
*/

contract AuriOracle is PriceOracle, BoringOwnable {
  struct AggregatedData {
    uint216 answer;
    uint8 underlyingDecimal; // must not be used anyway except in setUnderlyingDecimals
    uint32 updatedAt;
    // sum = 256 bit
  }

  struct RawData {
    uint216 answer;
    uint32 updatedAt;
    // sum < 256 bit
  }

  address public immutable updator1;
  address public immutable updator2;
  address public immutable updator3;

  mapping(address => mapping(address => RawData)) public mainFeedRaw; // updator => auToken => MainFeedRawData
  mapping(address => AggregatedData) public mainFeed; // auToken => MainFeedData

  mapping(address => address) public backupFeedAddr; // auToken => backupFeedAddr

  uint256 private constant _DEFAULT_PRICE_VALID_PERIOD = 5 minutes;
  uint256 private constant _DEFAULT_FUTURE_TOLERANCE = 3 seconds;
  uint256 private constant _1E10 = 1e10;

  uint256 public validPeriod;
  uint256 public futureTolerance;

  event MainFeedSync(address indexed auToken, uint256 indexed answer, address indexed updator);
  event MainFeedFail(address indexed auToken, address indexed updator);
  event BackupFeedUpdated(address indexed auToken, address indexed backupFeed);
  event DecimalsSet(address indexed auToken, uint8 indexed decimals);

  modifier onlyUpdator() {
    require(
      msg.sender == updator1 || msg.sender == updator2 || msg.sender == updator3,
      "not allowed"
    );
    _;
  }

  constructor(
    address _updator1,
    address _updator2,
    address _updator3
  ) BoringOwnable() {
    validPeriod = _DEFAULT_PRICE_VALID_PERIOD;
    futureTolerance = _DEFAULT_FUTURE_TOLERANCE;
    updator1 = _updator1;
    updator2 = _updator2;
    updator3 = _updator3;
  }

  function getUnderlyingPrices(AuToken[] calldata auTokens)
    external
    view
    override
    returns (uint256[] memory res)
  {
    res = new uint256[](auTokens.length);
    uint256 cachedValidPeriod = validPeriod;
    for (uint256 i = 0; i < auTokens.length; i++) {
      res[i] = _getUnderlyingPrice(auTokens[i], cachedValidPeriod);
    }
  }

  function getUnderlyingPrice(AuToken auToken) external view override returns (uint256) {
    return _getUnderlyingPrice(auToken, validPeriod);
  }

  function _getUnderlyingPrice(AuToken auToken, uint256 cachedValidPeriod)
    internal
    view
    returns (uint256)
  {
    AggregatedData memory mainFeedData = mainFeed[address(auToken)];
    (uint256 rawPrice, uint256 underlyingDecimal, uint256 updatedAt) = (
      mainFeedData.answer,
      mainFeedData.underlyingDecimal,
      mainFeedData.updatedAt
    );
    require(underlyingDecimal != 0, "underlyingDecimal not set");
    require(rawPrice != 0 && updatedAt != 0, "mainFeed data zero");

    if (isOutdated(updatedAt, cachedValidPeriod)) {
      (rawPrice, ) = fetchBackupFeed(backupFeedAddr[address(auToken)]);
    }

    // feed's price is 8 decimals, so we will multiply it by 1e10 to get 1e18 decimals
    uint256 rawPrice18Decimals = rawPrice * _1E10;

    // scale the price to price for 1e18 units
    if (underlyingDecimal <= 18) {
      return rawPrice18Decimals * (10**(18 - underlyingDecimal));
    } else {
      return rawPrice18Decimals / (10**(underlyingDecimal - 18));
    }
  }

  /**
    * @dev out of the 3 feeds, we will take the 2 non-outdated feeds with minimum difference between them,
    and then the final price will be the average of the two
    * @dev by doing this, even if one feed is down (outdated) or one feed is malicious, the system
    would still be able to run normally
    * @param newUpdatedAt the timestamp of the block that we query this price from
  */
  function updateMainFeedData(
    address auToken,
    int256 newUnderlyingPrice,
    uint256 newUpdatedAt
  ) external onlyUpdator {
    require(newUnderlyingPrice > 0, "bad price");
    if (block.timestamp > newUpdatedAt) {
      // reject stale price
      require(!isOutdated(newUpdatedAt, validPeriod), "price outdated");
    } else {
      // reject future timestamp (but accept a small delta of future time)
      require(newUpdatedAt - block.timestamp < futureTolerance, "future time rejected");
      newUpdatedAt = block.timestamp;
    }

    // safe uint256 cast since answer > 0
    mainFeedRaw[msg.sender][auToken] = RawData(
      Math.safe216(uint256(newUnderlyingPrice)),
      Math.safe32(newUpdatedAt)
    );

    (uint256 answer, uint256 updatedAt) = aggregateAllRawData(auToken);

    if (updatedAt != 0) {
      // updatedAt == 0 only if 2 out of 3 feeds are outdated
      // answer != 0 since updatedAt != 0
      mainFeed[auToken].answer = Math.safe216(answer);
      mainFeed[auToken].updatedAt = Math.safe32(updatedAt);
      emit MainFeedSync(auToken, uint256(answer), msg.sender);
    } else {
      emit MainFeedFail(auToken, msg.sender);
    }
  }

  /**
  @notice updatedAt & answer can be both zero when at least 2 of 3 feeds are outdated
  */
  function aggregateAllRawData(address auToken)
    internal
    view
    returns (uint256 answer, uint256 updatedAt)
  {
    RawData[3] memory data = [
      mainFeedRaw[updator1][auToken],
      mainFeedRaw[updator2][auToken],
      mainFeedRaw[updator3][auToken]
    ];

    uint256 cachedValidPeriod = validPeriod;
    uint256 mnDiff = type(uint256).max;

    // Looping through all pairs of prices to find the closest double
    for (uint8 i = 0; i < 3; i++) {
      uint8 j = (i + 1) % 3;
      if (
        isOutdated(data[i].updatedAt, cachedValidPeriod) ||
        isOutdated(data[j].updatedAt, cachedValidPeriod)
      ) continue;
      uint256 diff = Math.absDiff(data[i].answer, data[j].answer);
      if (diff < mnDiff) {
        (answer, updatedAt) = mergeTwoFeeds(data[i], data[j]);
        mnDiff = diff;
      }
    }
  }

  function mergeTwoFeeds(RawData memory feed1, RawData memory feed2)
    internal
    pure
    returns (uint256 answer, uint256 updatedAt)
  {
    answer = Math.average(feed1.answer, feed2.answer);
    updatedAt = Math.min(feed1.updatedAt, feed2.updatedAt);
  }

  function fetchBackupFeed(address feed) public view returns (uint256 answer, uint256 updatedAt) {
    // prettier-ignore
    (
      /*uint80 roundId*/,
      int256 rawAnswer,
      /*uint256 startedAt*/,
      uint256 rawUpdatedAt,
      /*uint80 answeredInRound*/
    ) = AggregatorV3Interface(feed).latestRoundData();

    require(rawAnswer > 0, "bad price");

    // safe cast since rawAnswer > 0
    answer = uint256(rawAnswer);
    updatedAt = rawUpdatedAt;
  }

  function isOutdated(uint256 lastUpdateTimestamp, uint256 localValidPeriod)
    internal
    view
    returns (bool res)
  {
    res = (block.timestamp - lastUpdateTimestamp) > localValidPeriod;
  }

  function setPriceValidity(uint256 _validPeriod) external onlyOwner {
    require(_validPeriod != 0, "bad input");
    validPeriod = _validPeriod;
  }

  function setFutureTolerance(uint256 _futureTolerance) external onlyOwner {
    require(_futureTolerance != 0, "bad input");
    futureTolerance = _futureTolerance;
  }

  function setBackupFeedAddr(address[] calldata auTokens, address[] calldata backupFeeds)
    external
    onlyOwner
  {
    require(auTokens.length == backupFeeds.length, "invalid length");
    for (uint256 i = 0; i < auTokens.length; i++) {
      backupFeedAddr[auTokens[i]] = backupFeeds[i];
      emit BackupFeedUpdated(auTokens[i], backupFeeds[i]);
    }
  }

  function setUnderlyingDecimals(address[] calldata auTokens, uint8[] calldata decimals)
    external
    onlyOwner
  {
    require(auTokens.length == decimals.length, "invalid length");
    for (uint256 i = 0; i < auTokens.length; i++) {
      mainFeed[auTokens[i]].underlyingDecimal = decimals[i];
      emit DecimalsSet(auTokens[i], decimals[i]);
    }
  }

  /**
  @dev ONLY USED FOR MONITORING PURPOSE
  @dev get the raw underlying price without any scaling
  */
  function _getRawUnderlyingPrice(AuToken auToken)
    external
    view
    returns (
      uint256 price,
      uint256 lastUpdated,
      bool isFromMainFeed
    )
  {
    AggregatedData memory mainFeedData = mainFeed[address(auToken)];
    (price, lastUpdated) = (mainFeedData.answer, mainFeedData.updatedAt);
    isFromMainFeed = true;

    if (isOutdated(lastUpdated, validPeriod)) {
      (price, lastUpdated) = fetchBackupFeed(backupFeedAddr[address(auToken)]);
      isFromMainFeed = false;
    }
  }
}
