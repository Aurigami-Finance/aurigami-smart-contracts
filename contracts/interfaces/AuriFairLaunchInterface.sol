pragma solidity 0.8.11;

interface AuriFairLaunchInterface {
  event AddNewPool(
    address indexed stakeToken,
    uint32 indexed startTime,
    uint32 indexed endTime,
    uint256[] rewardPerSeconds
  );
  event RenewPool(
    uint256 indexed pid,
    uint32 indexed startTime,
    uint32 indexed endTime,
    uint256[] rewardPerSeconds
  );
  event UpdatePool(uint256 indexed pid, uint32 indexed endTime, uint256[] rewardPerSecond);
  event Deposit(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed timestamp,
    uint256 amount
  );
  event Withdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed timestamp,
    uint256 amount
  );
  event Harvest(
    address indexed user,
    uint256 indexed pid,
    address indexed rewardToken,
    uint256 lockedAmount,
    uint256 timestamp
  );
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed timestamp,
    uint256 amount
  );
  event RewardTokenWithdrawn(address indexed owner, address indexed rewardToken, uint256 amount);

  function harvest(
    address account,
    uint256 _pid,
    uint256 _maxAmountToHarvest
  ) external;

  function getUserInfo(uint256 _pid, address _account)
    external
    view
    returns (
      uint256 amount,
      uint256[] memory unclaimedRewards,
      uint256[] memory lastRewardPerShares
    );

  function updateAndGetUserInfo(uint256 _pid, address _account)
    external
    returns (
      uint256 amount,
      uint256[] memory unclaimedRewards,
      uint256[] memory lastRewardPerShares
    );

  function updateMultiplePools(address account, uint256[] calldata _pids) external;
}
