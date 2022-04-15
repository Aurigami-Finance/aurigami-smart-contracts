pragma solidity 0.8.11;

import "./AuErc20.sol";
import "./AuToken.sol";
import "./interfaces/EIP20Interface.sol";
import "./governance/Ply.sol";
import "./interfaces/PriceOracle.sol";
import "./interfaces/PULPInterface.sol";
import "./interfaces/AuriFairLaunchInterface.sol";

interface ComptrollerLensInterface {
  function markets(address) external view returns (bool, uint256);

  function oracle() external view returns (PriceOracle);

  function getAccountLiquidity(address) external view returns (uint256, uint256);

  function getAssetsIn(address) external view returns (AuToken[] memory);

  function claimReward(uint8, address) external;

  function rewardAccrued(uint8, address) external view returns (uint256);

  function rewardSpeeds(
    uint8,
    address,
    bool
  ) external view returns (uint256);

  function borrowCaps(address) external view returns (uint256);

  function ply() external view returns (EIP20Interface);

  function aurora() external view returns (EIP20Interface);

  function pulp() external view returns (PULPInterface);
}

contract AuriLens {
  struct AuTokenMetadata {
    address auToken;
    uint256 exchangeRateCurrent;
    uint256 supplyRatePerBlock;
    uint256 borrowRatePerBlock;
    uint256 reserveFactorMantissa;
    uint256 totalBorrows;
    uint256 totalReserves;
    uint256 totalSupply;
    uint256 totalCash;
    bool isListed;
    uint256 collateralFactorMantissa;
    address underlyingAssetAddress;
    uint256 auTokenDecimals;
    uint256 underlyingDecimals;
    uint256 plyRewardSupplySpeed;
    uint256 plyRewardBorrowSpeed;
    uint256 auroraRewardSupplySpeed;
    uint256 auroraRewardBorrowSpeed;
    uint256 borrowCap;
  }

  struct RewardSpeeds {
    uint256 plyRewardSupplySpeed;
    uint256 plyRewardBorrowSpeed;
    uint256 auroraRewardSupplySpeed;
    uint256 auroraRewardBorrowSpeed;
  }

  struct AuTokenBalances {
    address auToken;
    uint256 balanceOf;
    uint256 borrowBalanceCurrent;
    uint256 balanceOfUnderlying;
    uint256 tokenBalance;
    uint256 tokenAllowance;
  }

  struct AuTokenUnderlyingPrice {
    address auToken;
    uint256 underlyingPrice;
  }

  struct RewardBalancesMetadata {
    uint256 plyBalance;
    uint256 auroraBalance;
    uint256 plyAccrued;
    uint256 auroraAccrued;
    uint256[] amounts;
    uint256[] unclaimedRewards;
    uint256[] lastRewardsPerShare;
  }

  struct AccountLimits {
    AuToken[] markets;
    uint256 liquidity;
    uint256 shortfall;
  }

  function getRewardSpeeds(ComptrollerLensInterface comptroller, AuToken auToken)
    public
    view
    returns (RewardSpeeds memory rewardSpeeds)
  {
    rewardSpeeds.plyRewardSupplySpeed = comptroller.rewardSpeeds(0, address(auToken), true);
    rewardSpeeds.plyRewardBorrowSpeed = comptroller.rewardSpeeds(0, address(auToken), false);
    rewardSpeeds.auroraRewardSupplySpeed = comptroller.rewardSpeeds(1, address(auToken), true);
    rewardSpeeds.auroraRewardBorrowSpeed = comptroller.rewardSpeeds(1, address(auToken), false);
  }

  function getAddresses(ComptrollerLensInterface comptroller)
    external
    view
    returns (
      address ply,
      address aurora,
      address pulp
    )
  {
    ply = address(comptroller.ply());
    aurora = address(comptroller.aurora());
    pulp = address(comptroller.pulp());
  }

  /**
    @dev only auToken.exchangeRateCurrent() is a non-view function
  */
  function auTokenMetadataNonView(AuToken auToken) public returns (AuTokenMetadata memory) {
    ComptrollerLensInterface comptroller = ComptrollerLensInterface(
      address(auToken.comptroller())
    );
    (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(auToken));
    address underlyingAssetAddress;
    uint256 underlyingDecimals;

    if (compareStrings(auToken.symbol(), "auETH")) {
      underlyingAssetAddress = address(0);
      underlyingDecimals = 18;
    } else {
      AuErc20 auErc20 = AuErc20(address(auToken));
      underlyingAssetAddress = auErc20.underlying();
      underlyingDecimals = EIP20Interface(auErc20.underlying()).decimals();
    }
    RewardSpeeds memory rewardSpeeds = getRewardSpeeds(comptroller, auToken);

    uint256 borrowCap = 0;
    (bool borrowCapSuccess, bytes memory borrowCapReturnData) = address(comptroller).staticcall(
      abi.encodePacked(comptroller.borrowCaps.selector, abi.encode(address(auToken)))
    );
    if (borrowCapSuccess) {
      borrowCap = abi.decode(borrowCapReturnData, (uint256));
    }

    return
      AuTokenMetadata({
        auToken: address(auToken),
        exchangeRateCurrent: auToken.exchangeRateCurrent(),
        supplyRatePerBlock: auToken.supplyRatePerTimestamp(),
        borrowRatePerBlock: auToken.borrowRatePerTimestamp(),
        reserveFactorMantissa: auToken.reserveFactorMantissa(),
        totalBorrows: auToken.totalBorrows(),
        totalReserves: auToken.totalReserves(),
        totalSupply: auToken.totalSupply(),
        totalCash: auToken.getCash(),
        isListed: isListed,
        collateralFactorMantissa: collateralFactorMantissa,
        underlyingAssetAddress: underlyingAssetAddress,
        auTokenDecimals: auToken.decimals(),
        underlyingDecimals: underlyingDecimals,
        plyRewardSupplySpeed: rewardSpeeds.plyRewardSupplySpeed,
        plyRewardBorrowSpeed: rewardSpeeds.plyRewardBorrowSpeed,
        auroraRewardSupplySpeed: rewardSpeeds.auroraRewardSupplySpeed,
        auroraRewardBorrowSpeed: rewardSpeeds.auroraRewardBorrowSpeed,
        borrowCap: borrowCap
      });
  }

  function auTokenMetadataAllNonView(AuToken[] calldata auTokens)
    external
    returns (AuTokenMetadata[] memory)
  {
    uint256 auTokenCount = auTokens.length;
    AuTokenMetadata[] memory res = new AuTokenMetadata[](auTokenCount);
    for (uint256 i = 0; i < auTokenCount; i++) {
      res[i] = auTokenMetadataNonView(auTokens[i]);
    }
    return res;
  }

  /**
    @dev only borrowBalanceCurrent & balanceOfUnderlying are non-view functions
  */
  function auTokenBalances(AuToken auToken) public returns (AuTokenBalances memory) {
    uint256 tokenBalance;
    uint256 tokenAllowance;

    if (compareStrings(auToken.symbol(), "auETH")) {
      tokenBalance = msg.sender.balance;
      tokenAllowance = msg.sender.balance;
    } else {
      EIP20Interface underlying = EIP20Interface(AuErc20(address(auToken)).underlying());
      tokenBalance = underlying.balanceOf(msg.sender);
      tokenAllowance = underlying.allowance(msg.sender, address(auToken));
    }

    return
      AuTokenBalances({
        auToken: address(auToken),
        balanceOf: auToken.balanceOf(msg.sender),
        borrowBalanceCurrent: auToken.borrowBalanceCurrent(msg.sender),
        balanceOfUnderlying: auToken.balanceOfUnderlying(msg.sender),
        tokenBalance: tokenBalance,
        tokenAllowance: tokenAllowance
      });
  }

  function auTokenBalancesAll(AuToken[] calldata auTokens)
    external
    returns (AuTokenBalances[] memory)
  {
    uint256 auTokenCount = auTokens.length;
    AuTokenBalances[] memory res = new AuTokenBalances[](auTokenCount);
    for (uint256 i = 0; i < auTokenCount; i++) {
      res[i] = auTokenBalances(auTokens[i]);
    }
    return res;
  }

  function auTokenUnderlyingPrice(AuToken auToken)
    public
    view
    returns (AuTokenUnderlyingPrice memory)
  {
    ComptrollerLensInterface comptroller = ComptrollerLensInterface(
      address(auToken.comptroller())
    );
    PriceOracle priceOracle = comptroller.oracle();

    return
      AuTokenUnderlyingPrice({
        auToken: address(auToken),
        underlyingPrice: priceOracle.getUnderlyingPrice(auToken)
      });
  }

  function auTokenUnderlyingPriceAll(AuToken[] calldata auTokens)
    external
    view
    returns (AuTokenUnderlyingPrice[] memory)
  {
    uint256 auTokenCount = auTokens.length;
    AuTokenUnderlyingPrice[] memory res = new AuTokenUnderlyingPrice[](auTokenCount);
    for (uint256 i = 0; i < auTokenCount; i++) {
      res[i] = auTokenUnderlyingPrice(auTokens[i]);
    }
    return res;
  }

  function getAccountLimits(ComptrollerLensInterface comptroller)
    public
    view
    returns (AccountLimits memory)
  {
    (uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(msg.sender);

    return
      AccountLimits({
        markets: comptroller.getAssetsIn(msg.sender),
        liquidity: liquidity,
        shortfall: shortfall
      });
  }

  /**
   * @dev only 2 claimReward are non-view functions
   * @dev to be impersonated and callStatic by SDK
   */
  function claimAndGetRewardBalancesMetadata(
    ComptrollerLensInterface comptroller,
    AuriFairLaunchInterface auriFairLaunch,
    uint256[] calldata pids
  ) external returns (RewardBalancesMetadata memory rewardData) {
    EIP20Interface ply = comptroller.ply();
    EIP20Interface aurora = comptroller.aurora();
    PULPInterface pulp = PULPInterface(comptroller.pulp());

    rewardData.plyBalance = ply.balanceOf(msg.sender);
    rewardData.auroraBalance = aurora.balanceOf(msg.sender);

    // state-change
    comptroller.claimReward(0, msg.sender);
    // state-change
    comptroller.claimReward(1, msg.sender);

    // handle ply
    uint256 newPlyBalance = ply.balanceOf(msg.sender);
    uint256 plyReceivedFromComptroller = newPlyBalance - rewardData.plyBalance;
    uint256 plyLocked = comptroller.rewardAccrued(0, msg.sender) +
      pulp.balanceOf(msg.sender) -
      pulp.getMaxAmountRedeemable(msg.sender);
    rewardData.plyAccrued = plyLocked + plyReceivedFromComptroller;

    // handle aurora
    uint256 newAuroraBalance = aurora.balanceOf(msg.sender);
    rewardData.auroraAccrued = newAuroraBalance - rewardData.auroraBalance;

    // get rewards from fairlaunch
    rewardData.amounts = new uint256[](pids.length);
    rewardData.unclaimedRewards = new uint256[](pids.length);
    rewardData.lastRewardsPerShare = new uint256[](pids.length);
    for (uint256 i = 0; i < pids.length; i++) {
      (
        rewardData.amounts[i],
        rewardData.unclaimedRewards[i],
        rewardData.lastRewardsPerShare[i]
      ) = auriFairLaunch.updateAndGetUserInfo(pids[i], msg.sender);
    }
  }

  /**
   * @dev comptroller.claimReward, fairlaunch.harvest & tokenLock.claim are non-view
   * @dev to be impersonated and callStatic by SDK
   */
  function claimRewards(
    ComptrollerLensInterface comptroller,
    AuriFairLaunchInterface fairLaunch,
    uint256[] calldata pids
  ) external {
    // claim comp accrued rewards
    comptroller.claimReward(0, msg.sender);
    comptroller.claimReward(1, msg.sender);

    // claim fairlaunch rewards
    for (uint256 i; i < pids.length; i++) {
      fairLaunch.harvest(msg.sender, pids[i], type(uint256).max);
    }
  }

  function compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }
}
