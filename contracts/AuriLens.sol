pragma solidity 0.8.11;

import "./AuErc20.sol";
import "./AuToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/PriceOracle.sol";
import "./interfaces/PULPInterface.sol";
import "./interfaces/AuriFairLaunchInterface.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./BoringOwnableUpgradeable.sol";

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

  function ply() external view returns (IERC20);

  function aurora() external view returns (IERC20);

  function pulp() external view returns (PULPInterface);
}

contract AuriLens is Initializable, BoringOwnableUpgradeable, UUPSUpgradeable {
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
    uint256 plyAccrured;
    uint256 auroraClaimable;
    uint256 wnearClaimable;
  }

  struct AccountLimits {
    AuToken[] markets;
    uint256 liquidity;
    uint256 shortfall;
  }

  IERC20 public immutable WNEAR;

  constructor(IERC20 _WNEAR) initializer {
    WNEAR = _WNEAR;
  }

  function initialize() external initializer {
    __BoringOwnable_init();
  }

  function _authorizeUpgrade(address) internal virtual override onlyOwner {}

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
      address wnear,
      address pulp
    )
  {
    ply = address(comptroller.ply());
    aurora = address(comptroller.aurora());
    pulp = address(comptroller.pulp());
    wnear = address(WNEAR);
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
      underlyingDecimals = IERC20Metadata(auErc20.underlying()).decimals();
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
      IERC20 underlying = IERC20(AuErc20(address(auToken)).underlying());
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
   * @dev comptroller.claimReward, fairlaunch.harvest & pulp.redeem are non-view
   * @dev to be impersonated and callStatic by SDK
   */
  function claimRewards(
    ComptrollerLensInterface comptroller,
    AuriFairLaunchInterface fairLaunch,
    uint256[] calldata pids
  ) external returns (RewardBalancesMetadata memory rewardData) {
    /// ------------------------------------------------------------
    /// set-up states
    /// ------------------------------------------------------------

    IERC20 ply = comptroller.ply();
    IERC20 aurora = comptroller.aurora();
    IERC20 wnear = WNEAR;
    PULPInterface pulp = PULPInterface(comptroller.pulp());

    uint256 plyBalance = ply.balanceOf(msg.sender);
    uint256 pulpBalance = pulp.balanceOf(msg.sender);
    uint256 auroraBalance = aurora.balanceOf(msg.sender);
    uint256 wnearBalance = wnear.balanceOf(msg.sender);

    /// ------------------------------------------------------------
    /// claim rewards
    /// ------------------------------------------------------------

    comptroller.claimReward(0, msg.sender);
    comptroller.claimReward(1, msg.sender);
    for (uint256 i; i < pids.length; i++) {
      fairLaunch.harvest(msg.sender, pids[i], type(uint256).max);
    }

    /// ------------------------------------------------------------
    /// calc redeemed amounts
    /// ------------------------------------------------------------

    // only ply,aurora and wnear will be rewarded to users
    rewardData.plyAccrured =
      ply.balanceOf(msg.sender) -
      plyBalance +
      pulp.balanceOf(msg.sender) -
      pulpBalance;
    rewardData.auroraClaimable = aurora.balanceOf(msg.sender) - auroraBalance;
    rewardData.wnearClaimable = wnear.balanceOf(msg.sender) - wnearBalance;
  }

  function compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }

  /**
   * @dev Get percentage lock of a user in a specific week
   */
  function getPercentLock(
    PULPInterface pulp,
    address account,
    int256 weekInt
  ) public view returns (uint256 percentLock) {
    if (weekInt < 0) return 10_000;

    uint256 week = uint256(weekInt);

    (bool _isSet, uint224 _percentLock) = pulp.userLock(account, week);
    if (_isSet) {
      percentLock = _percentLock;
    } else {
      percentLock = pulp.globalLock(week);
    }
  }

  /**
   * @dev Get the first week that the unlock percentage reach the target
   * @dev This function is very gas intensive & is intended to be called by SDK
   */
  function getWeekToUnlock(
    PULPInterface pulp,
    address account,
    uint256 targetUnlockPercent
  ) external view returns (int256) {
    uint256 targetLockPercent = 10_000 - targetUnlockPercent;
    for (int256 i = 0; i <= 47; i++) {
      if (getPercentLock(pulp, account, i) <= targetLockPercent) {
        return i;
      }
    }
    return 48;
  }
}
