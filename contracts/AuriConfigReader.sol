pragma solidity 0.8.11;
import "./AuToken.sol";
import "./AuErc20.sol";
import "./Comptroller.sol";
import "./PULP.sol";
import "./JumpRateModel.sol";
import "./AuriOracle.sol";

contract AuriConfigReader {
  struct ComptrollerConfig {
    address comptroller_admin;
    address comptrollerImplementation;
    address oracle;
    uint256 closeFactorMantissa;
    uint256 liquidationIncentiveMantissa;
    uint256 maxAssets;
    address pauseGuardian;
    address borrowCapGuardian;
    address ply;
    address aurora;
    address pulp;
    uint32 rewardClaimStart;
    address pulp_unitroller;
    uint256 multiplierPerTimestamp;
    uint256 baseRatePerTimestamp;
    uint256 jumpMultiplierPerTimestamp;
    uint256 kink;
    address oracle_updator1;
    address oracle_updator2;
    address oracle_updator3;
    uint256 oracle_validPeriod;
    uint256 oracle_futureTolerance;
    address oracle_admin;
    // skip borrowCaps
  }

  struct AuTokenImmutableData {
    string name;
    string symbol;
    uint8 decimals;
    address admin;
    address underlying;
    uint256 reserveFactorMantissa;
    uint256 protocolSeizeShareMantissa;
    uint256 collateralFactorMantissa;
    uint256 rewardSpeedsBorrow_PLY;
    uint256 rewardSpeedsSupply_PLY;
    uint256 rewardSpeedsBorrow_AURORA;
    uint256 rewardSpeedsSupply_AURORA;
  }

  struct AuTokenVolatileData {
    string name;
    uint256 accrualBlockTimestamp;
    uint256 borrowIndex;
    uint256 totalBorrows;
    uint256 totalReserves;
    uint256 totalSupply;
    uint256 exchangeRateCurrent;
    uint256 cash;
    // uint224 rewardSupplyState_index_PLY;
    // uint32 rewardSupplyState_timestamp_PLY;
    // uint224 rewardBorrowState_index_PLY;
    // uint32 rewardBorrowState_timestamp_PLY;
    // uint224 rewardSupplyState_index_AURORA;
    // uint32 rewardSupplyState_timestamp_AURORA;
    // uint224 rewardBorrowState_index_AURORA;
    // uint32 rewardBorrowState_timestamp_AURORA;
    uint216 oracle_answer;
    uint8 oracle_underlyingDecimal;
    uint32 oracle_updatedAt;
    address oracle_backupFeed;
    bool oracle_isMainfeedOutdated;
  }

  Comptroller public immutable comp;
  JumpRateModel public immutable model;

  constructor(Comptroller _comp, JumpRateModel _model) {
    comp = _comp;
    model = _model;
  }

  function readComptroller() external view returns (ComptrollerConfig memory data) {
    data.comptroller_admin = comp.admin();
    data.comptrollerImplementation = comp.comptrollerImplementation();
    data.oracle = address(comp.oracle());
    data.closeFactorMantissa = comp.closeFactorMantissa();
    data.liquidationIncentiveMantissa = comp.liquidationIncentiveMantissa();
    data.maxAssets = comp.maxAssets();
    data.pauseGuardian = comp.pauseGuardian();
    data.borrowCapGuardian = comp.borrowCapGuardian();
    data.ply = address(comp.ply());
    data.aurora = address(comp.aurora());
    data.pulp = address(comp.pulp());
    data.rewardClaimStart = comp.rewardClaimStart();

    data.pulp_unitroller = address(PULP(data.pulp).unitroller());

    data.multiplierPerTimestamp = model.multiplierPerTimestamp();
    data.baseRatePerTimestamp = model.baseRatePerTimestamp();
    data.jumpMultiplierPerTimestamp = model.jumpMultiplierPerTimestamp();
    data.kink = model.kink();

    AuriOracle oracle = AuriOracle(data.oracle);
    data.oracle_updator1 = oracle.updator1();
    data.oracle_updator2 = oracle.updator2();
    data.oracle_updator3 = oracle.updator3();
    data.oracle_validPeriod = oracle.validPeriod();
    data.oracle_futureTolerance = oracle.futureTolerance();
    data.oracle_admin = oracle.owner();
  }

  function readAuTokenImmutable(AuToken auToken)
    public
    view
    returns (AuTokenImmutableData memory data)
  {
    data.name = auToken.name();
    data.symbol = auToken.symbol();
    data.decimals = auToken.decimals();
    data.admin = auToken.admin();
    data.reserveFactorMantissa = auToken.reserveFactorMantissa();
    data.protocolSeizeShareMantissa = auToken.protocolSeizeShareMantissa();
    if (!compareStrings(data.symbol, "auETH")) {
      data.underlying = AuErc20Storage(address(auToken)).underlying();
    }
    (, data.collateralFactorMantissa, ) = comp.markets(address(auToken));
    data.rewardSpeedsBorrow_PLY = comp.rewardSpeeds(0, address(auToken), false);
    data.rewardSpeedsSupply_PLY = comp.rewardSpeeds(0, address(auToken), true);
    data.rewardSpeedsBorrow_AURORA = comp.rewardSpeeds(1, address(auToken), false);
    data.rewardSpeedsSupply_AURORA = comp.rewardSpeeds(1, address(auToken), true);

    require(address(auToken.comptroller()) == address(comp), "wrong comp");
    require(address(auToken.interestRateModel()) == address(model), "wrong interest rate model");
  }

  function readAuTokenVolatile(AuToken auToken)
    public
    view
    returns (AuTokenVolatileData memory data)
  {
    data.name = auToken.name();
    data.accrualBlockTimestamp = auToken.accrualBlockTimestamp();
    data.borrowIndex = auToken.borrowIndex();
    data.totalBorrows = auToken.totalBorrows();
    data.totalReserves = auToken.totalReserves();
    data.totalSupply = auToken.totalSupply();
    data.exchangeRateCurrent = auToken.exchangeRateStored();
    data.cash = auToken.getCash();
    // (data.rewardSupplyState_index_PLY, data.rewardSupplyState_timestamp_PLY) = comp
    //   .rewardSupplyState(0, address(auToken));
    // (data.rewardBorrowState_index_PLY, data.rewardBorrowState_timestamp_PLY) = comp
    //   .rewardBorrowState(0, address(auToken));

    // (data.rewardSupplyState_index_AURORA, data.rewardSupplyState_timestamp_AURORA) = comp
    //   .rewardSupplyState(1, address(auToken));
    // (data.rewardBorrowState_index_AURORA, data.rewardBorrowState_timestamp_AURORA) = comp
    //   .rewardBorrowState(1, address(auToken));

    AuriOracle oracle = AuriOracle(address(comp.oracle()));
    (data.oracle_answer, data.oracle_underlyingDecimal, data.oracle_updatedAt) = oracle.mainFeed(
      address(auToken)
    );
    data.oracle_backupFeed = oracle.backupFeedAddr(address(auToken));
    data.oracle_isMainfeedOutdated =
      (block.timestamp - data.oracle_updatedAt) > oracle.validPeriod();
  }

  function readAllAuTokensImmutable() external view returns (AuTokenImmutableData[] memory data) {
    AuToken[] memory auTokens = comp.getAllMarkets();
    data = new AuTokenImmutableData[](auTokens.length);
    for (uint256 i = 0; i < data.length; i++) {
      data[i] = readAuTokenImmutable(auTokens[i]);
    }
  }

  function readAllAuTokensVolatile() external view returns (AuTokenVolatileData[] memory data) {
    AuToken[] memory auTokens = comp.getAllMarkets();
    data = new AuTokenVolatileData[](auTokens.length);
    for (uint256 i = 0; i < data.length; i++) {
      data[i] = readAuTokenVolatile(auTokens[i]);
    }
  }

  function compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }
}
