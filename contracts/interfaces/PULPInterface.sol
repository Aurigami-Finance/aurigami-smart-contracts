// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface PULPInterface is IERC20Metadata {
  function globalLock(uint256 _week) external view returns (uint256);

  function userLock(address _user, uint256 _week) external view returns (bool, uint224);

  function PLY() external view returns (address);

  function lockPly(address recipient, uint256 amount) external;

  function calcLockAmount(address account, uint256 amount)
    external
    view
    returns (uint256 lockAmount, uint256 claimAmount);

  function redeem(address recipient, uint256 amountToRedeem)
    external
    returns (uint256 amountRedeemed);

  function getMaxAmountRedeemable(address account) external view returns (uint256 res);

  event PlyLocked(address indexed locker, address indexed recipient, uint256 amount);

  event GlobalLockSet(uint256 indexed weekNumber, uint256 newPercentLock);

  event UserLockSet(address indexed account, uint256 indexed weekNumber, uint256 newPercentLock);

  event PulpRedeemed(address indexed redeemer, address indexed recipient, uint256 amount);

  event EarlyRedeemAdd(address indexed account, uint256 amountAdd);

  event EarlyRedeemReset(address indexed account, uint256 newAmount);
}
