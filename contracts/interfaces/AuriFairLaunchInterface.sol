pragma solidity 0.8.11;

interface AuriFairLaunchInterface {
  function harvest(address account, uint256 _pid, uint256 _maxAmountToHarvest) external;

  function getUserInfo(uint256 _pid, address _account)
    external
    view
    returns (
      uint256 amount,
      uint256 unclaimedReward,
      uint256 lastRewardPerShare
    );

  function updateAndGetUserInfo(uint256 _pid, address _account)
    external
    returns (
      uint256 amount,
      uint256 unclaimedReward,
      uint256 lastRewardPerShare
    );

  function updateMultiplePools(address account, uint256[] calldata _pids) external;
}