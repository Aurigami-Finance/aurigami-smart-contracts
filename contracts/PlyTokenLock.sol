// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BoringOwnable.sol";

/**
 * @dev Time-locks tokens according to an unlock schedule.
 */
contract PlyTokenLock is BoringOwnable {
  using SafeERC20 for IERC20;

  IERC20 public immutable ply;
  uint256 public immutable unlockBegin;
  uint256 public immutable unlockCliff;
  uint256 public immutable unlockEnd;

  mapping(address => uint256) public lockedAmounts;
  mapping(address => uint256) public claimedAmounts;

  event Locked(address indexed sender, address indexed recipient, uint256 amount);
  event Claimed(address indexed sender, address indexed recipient, uint256 amount);
  event ForceTransferVesting(
    address indexed from,
    address indexed to,
    uint256 amountLocked,
    uint256 amountClaimed
  );

  /**
   * @dev Constructor.
   * @param _unlockBegin The time at which unlocking of tokens will be gin.
   * @param _unlockCliff The first time at which tokens are claimable.
   * @param _unlockEnd The time at which the last token will unlock.
   */
  constructor(
    IERC20 _ply,
    uint256 _unlockBegin,
    uint256 _unlockCliff,
    uint256 _unlockEnd
  ) {
    require(_unlockCliff >= _unlockBegin, "Unlock cliff must not be before unlock begin");
    require(_unlockEnd >= _unlockCliff, "Unlock end must not be before unlock cliff");
    ply = _ply;
    unlockBegin = _unlockBegin;
    unlockCliff = _unlockCliff;
    unlockEnd = _unlockEnd;
  }

  /**
   * @dev Returns the maximum number of tokens currently claimable by `user`.
   * @param user The account to check the claimable balance of.
   * @return The number of tokens currently claimable.
   */
  function claimableBalance(address user) public view returns (uint256) {
    if (block.timestamp < unlockCliff) {
      return 0;
    }

    uint256 locked = lockedAmounts[user];
    uint256 claimed = claimedAmounts[user];
    if (block.timestamp >= unlockEnd) {
      return locked - claimed;
    }
    return (locked * (block.timestamp - unlockBegin)) / (unlockEnd - unlockBegin) - claimed;
  }

  /**
   * @dev Transfers tokens from the caller to the token lock contract and locks them for benefit of `recipient`.
   *      Requires that the caller has authorised this contract with the token contract.
   * @param recipients The accounts the tokens will be claimable by.
   * @param amounts The numbers of tokens to transfer and lock.
   */
  function lock(address[] memory recipients, uint256[] memory amounts) external {
    require(block.timestamp < unlockEnd, "TokenLock: Unlock period already complete");
    require(recipients.length == amounts.length, "TokenLock: Invalid arrays");

    uint256 sumPlyLocked = 0;
    for (uint256 i = 0; i < recipients.length; i++) {
      require(recipients[i] != address(0), "zero address");
      lockedAmounts[recipients[i]] += amounts[i];
      sumPlyLocked += amounts[i];
      emit Locked(msg.sender, recipients[i], amounts[i]);
    }
    ply.safeTransferFrom(msg.sender, address(this), sumPlyLocked);
  }

  /**
   * @dev Claims the caller's tokens that have been unlocked, sending them to `recipient`.
   * @param recipient The account to transfer unlocked tokens to.
   * @param amount The amount to transfer. If greater than the claimable amount, the maximum is transferred.
   * @return amountOut the amount claimed
   */
  function claim(address recipient, uint256 amount) external returns (uint256 amountOut) {
    require(recipient != address(0), "zero address");

    uint256 claimable = claimableBalance(msg.sender);
    if (amount > claimable) {
      amount = claimable;
    }
    claimedAmounts[msg.sender] += amount;
    ply.safeTransfer(recipient, amount);

    amountOut = amount;
    emit Claimed(msg.sender, recipient, amount);
  }

  /// ------------------------------------------------------------
  /// owner-only-functions
  /// ------------------------------------------------------------

  function forceTransferVesting(address from, address to) external onlyOwner {
    require(to != address(0), "zero address");
    require(from != to, "from must not be the same as to");

    emit ForceTransferVesting(from, to, lockedAmounts[from], claimedAmounts[from]);

    claimedAmounts[to] += claimedAmounts[from];
    claimedAmounts[from] = 0;

    lockedAmounts[to] += lockedAmounts[from];
    lockedAmounts[from] = 0;
  }
}
