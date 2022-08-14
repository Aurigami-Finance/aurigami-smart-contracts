import "./../BoringOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

pragma solidity 0.8.11;

contract PlyGameSettings is BoringOwnableUpgradeable {
  using SafeCast for uint256;
  using SafeCast for uint128;
  using SafeCast for uint64;

  IERC20Upgradeable public immutable ply;
  address public house;

  uint128 public minAmount;
  uint128 public maxAmount;

  uint64 public bigWinProb;
  uint64 public winProb;
  uint64 public loseProb;
  uint64 public noImpactProb;

  constructor(address _ply) {
    ply = IERC20Upgradeable(_ply);
  }

  modifier onlyHouse() {
    require(msg.sender == house, "Caller is not the house");
    _;
  }

  /// @dev house can be the same as owner
  function setHouse(address newHouse) external onlyOwner {
    require(newHouse != address(0), "Invalid house");
    house = newHouse;
  }

  function setLimits(uint256 minAmount_, uint256 maxAmount_) external onlyOwner {
    require(minAmount_ > 0, "Invalid amount");
    require(minAmount_ <= maxAmount_, "Min less than max");
    minAmount = minAmount_.toUint128();
    maxAmount = maxAmount_.toUint128();
  }

  function setOdds(
    uint256 bigWinProb_,
    uint256 winProb_,
    uint256 loseProb_,
    uint256 noImpactProb_
  ) external onlyOwner {
    require(
      bigWinProb_ + winProb_ + loseProb_ + noImpactProb_ == 10000,
      "Probability should add up to 10000"
    );

    bigWinProb = bigWinProb_.toUint64();
    winProb = winProb_.toUint64();
    loseProb = loseProb_.toUint64();
    noImpactProb = noImpactProb_.toUint64();
  }
}
