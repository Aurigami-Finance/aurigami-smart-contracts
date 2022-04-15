// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/PULPInterface.sol";
import "./interfaces/RewardsClaimInterface.sol";
import "./BoringOwnable.sol";
import "./AuriMathLib.sol";

// solhint-disable var-name-mixedcase
contract PULP is ERC20, PULPInterface, BoringOwnable {
  using SafeERC20 for IERC20;

  struct UserLock {
    bool isSet;
    uint224 percentLock;
  }

  address public immutable PLY;
  RewardsClaimInterface public immutable unitroller;

  mapping(uint256 => uint256) public globalLock;

  // individual lock data for users (will override the global lock if applicable)
  mapping(address => mapping(uint256 => UserLock)) public userLock;

  // amount of early redemption allowed for each user (can be modified by admin)
  mapping(address => uint256) public earlyRedeems;

  uint256 public constant PULP_FIRST_REDEEM_WEEK = 49 + 27;

  constructor(address _PLY, RewardsClaimInterface _unitroller) ERC20("PULP", "PULP") {
    require(address(_PLY) != address(0), "null address");
    require(address(_unitroller) != address(0), "null address");
    PLY = _PLY;
    unitroller = _unitroller;

    // set percent locks
    // Take reference from rewardClaimStart:
    // week 0 = first 7 days after rewardClaimStart
    // week 1 = Days 8 to 14 after rewardClaimStart etc.
    // starting from week 0: 95% lock, -2% every subsequent week
    // will hit 1% on week 47
    for (uint256 i = 0; i <= 47; i++) {
      // base unlock: 5% (take inverse of it)
      // 100% = 10_000
      // Eg. week 2 = 10_000 - (5 + 2 * 2) * 100 = 9100 = 91%
      globalLock[i] = 10_000 - (5 + i * 2) * 100;
    }
    // week 48 onwards: 0%
  }

  /*///////////////////////////////////////////////////////////////
                    MINTING & LOCKING
  //////////////////////////////////////////////////////////////*/

  /// @notice convert PLY to PULP with 1-1 ratio
  function lockPly(address recipient, uint256 amount) external {
    require(recipient != address(0), "zero address");
    if (amount == 0) return;

    IERC20(PLY).safeTransferFrom(msg.sender, address(this), amount);
    _mint(recipient, amount);

    emit PlyLocked(msg.sender, recipient, amount);
  }

  /// @notice calculate the amount of PLY & PULP to transfer/mint.
  function calcLockAmount(address account, uint256 amount)
    external
    view
    returns (uint256 lockAmount, uint256 claimAmount)
  {
    int256 curWeekInt = getCurrentWeek();
    if (curWeekInt < 0) return (amount, 0);
    uint256 curWeek = uint256(curWeekInt);

    uint256 percentLock;

    // if userLock is set, use that number instead
    if (userLock[account][curWeek].isSet) {
      percentLock = userLock[account][curWeek].percentLock;
    } else {
      percentLock = globalLock[curWeek];
    }

    lockAmount = (amount * percentLock) / 10_000;
    claimAmount = amount - lockAmount;
  }

  function setGlobalLock(uint256[] calldata weekNumbers, uint256[] calldata values)
    external
    onlyOwner
  {
    require(weekNumbers.length == values.length, "bad array lengths");
    for (uint256 i = 0; i < weekNumbers.length; i++) {
      require(values[i] <= 10_000, "exceed max value");
      globalLock[weekNumbers[i]] = values[i];

      emit GlobalLockSet(weekNumbers[i], values[i]);
    }
  }

  function setUserLock(
    address account,
    uint256[] calldata weekNumbers,
    uint256[] calldata values
  ) external onlyOwner {
    require(weekNumbers.length == values.length, "bad array lengths");
    for (uint256 i = 0; i < weekNumbers.length; i++) {
      require(values[i] <= 10_000, "exceed max value");
      userLock[account][weekNumbers[i]] = UserLock(true, Math.safe224(values[i]));

      emit UserLockSet(account, weekNumbers[i], values[i]);
    }
  }

  /*///////////////////////////////////////////////////////////////
                    REDEMPTION OF PULP
  //////////////////////////////////////////////////////////////*/

  /// @notice set amount to type(uint256).max for max redeem
  function redeem(address recipient, uint256 amountToRedeem)
    external
    returns (uint256 amountRedeemed)
  {
    require(recipient != address(0), "zero address");
    require(amountToRedeem != 0, "zero amount");

    int256 curWeek = getCurrentWeek();
    require(curWeek >= 0, "wait until rewardClaimStart");

    if (amountToRedeem == type(uint256).max) {
      amountToRedeem = _getMaxAmountRedeemable(msg.sender, curWeek);
    }

    if (!isPulpUnlocked(curWeek)) {
      require(earlyRedeems[msg.sender] >= amountToRedeem, "insufficient earlyRedeems");
      earlyRedeems[msg.sender] -= amountToRedeem;
    }

    _burn(msg.sender, amountToRedeem);
    IERC20(PLY).safeTransfer(recipient, amountToRedeem);
    amountRedeemed = amountToRedeem;

    emit PulpRedeemed(msg.sender, recipient, amountRedeemed);
  }

  function getMaxAmountRedeemable(address account) external view returns (uint256 res) {
    res = _getMaxAmountRedeemable(account, getCurrentWeek());
  }

  function _getMaxAmountRedeemable(address account, int256 curWeek)
    internal
    view
    returns (uint256 res)
  {
    res = balanceOf(account);

    if (!isPulpUnlocked(curWeek)) {
      res = Math.min(res, earlyRedeems[account]);
    }
  }

  /// @notice preferable way to modify earlyRedeems. Note that once earlyRedeems for an user
  /// is added, the user can redeem it right away. Hence, make sure to double check before
  /// any data is sent
  function addEarlyRedeems(address[] calldata accounts, uint256[] calldata data) public onlyOwner {
    require(accounts.length == data.length, "array lengths mismatch");
    for (uint256 i = 0; i < accounts.length; i++) {
      earlyRedeems[accounts[i]] += data[i];

      emit EarlyRedeemAdd(accounts[i], data[i]);
    }
  }

  /// @notice non-preferable way to modify earlyRedeems
  function resetEarlyRedeems(address[] calldata accounts, uint256[] calldata data)
    public
    onlyOwner
  {
    require(accounts.length == data.length, "array lengths mismatch");
    for (uint256 i = 0; i < accounts.length; i++) {
      earlyRedeems[accounts[i]] = data[i];

      emit EarlyRedeemReset(accounts[i], data[i]);
    }
  }

  /*///////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function getCurrentWeek() public view returns (int256) {
    // week 0 = first 7 days after rewardClaimStart
    // week 1 = Days 8 to 14 after rewardClaimStart etc.
    return (int256(block.timestamp) - int32(unitroller.rewardClaimStart())) / 7 days;
  }

  function isPulpUnlocked(int256 curWeek) public pure returns (bool) {
    return curWeek >= int256(PULP_FIRST_REDEEM_WEEK);
  }

  function _beforeTokenTransfer(
    address,
    address to,
    uint256
  ) internal view override {
    require(to != address(this), "fobidden");
  }
}
