// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/PULPInterface.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import "./AuriMathLib.sol";
import "./interfaces/AuriFairLaunchInterface.sol";

interface ComptrollerInterface {
  function isAllowedToClaimReward(address user, address claimer) external view returns (bool);
}

/// @author Kyber Network
/// Forked from KyberFairLaunch
/// Allow stakers to stake LP tokens and receive a reward token
/// Allow extend or renew a pool to continue/restart the LM program
/// When harvesting, rewards will be transferred according to schedule dictated by TokenLock
contract AuriFairLaunch is ReentrancyGuard, BoringOwnable, AuriFairLaunchInterface {
  using SafeCast for uint256;
  using SafeERC20 for IERC20;

  uint256 internal constant PRECISION = 1e12;

  struct UserRewardData {
    uint256 unclaimedReward;
    uint256 lastRewardPerShare;
  }
  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many Staking tokens the user has provided.
    mapping(uint256 => UserRewardData) userRewardData;
    //
    // Basically, any point in time, the amount of reward token
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = user.unclaimAmount + (user.amount * (pool.accRewardPerShare - user.lastRewardPerShare)
    //
    // Whenever a user deposits or withdraws Staking tokens to a pool. Here's what happens:
    //   1. The pool's `accRewardPerShare` (and `lastRewardTimestamp`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `lastRewardPerShare` gets updated.
    //   4. User's `amount` gets updated.
  }

  struct PoolRewardData {
    uint256 rewardPerSecond;
    uint256 accRewardPerShare;
  }
  // Info of each pool
  // poolRewardData: reward data for each reward token
  //      rewardPerSecond: amount of reward token per second
  //      accRewardPerShare: accumulated reward per share of token
  // totalStake: total amount of stakeToken has been staked
  // stakeToken: token to stake, should be an ERC20 token
  // startTime: the timestamp that the reward starts
  // endTime: the timestamp that the reward ends
  // lastRewardTimestamp: last timestamp that rewards distribution occurs
  struct PoolInfo {
    uint256 totalStake;
    address stakeToken;
    uint32 startTime;
    uint32 endTime;
    uint32 lastRewardTimestamp;
    mapping(uint256 => PoolRewardData) poolRewardData;
  }

  // check if a pool exists for a stakeToken
  mapping(address => bool) public poolExists;
  // contract for locking reward
  PULPInterface public immutable pulp;
  IERC20 public immutable ply;
  address[] public rewardTokens;

  // comptroller to determine who can harvest
  ComptrollerInterface public immutable unitroller;

  // Info of each pool.
  uint256 public poolLength;
  mapping(uint256 => PoolInfo) internal poolInfo;
  // Info of each user that stakes Staking tokens.
  mapping(uint256 => mapping(address => UserInfo)) internal userInfo;

  constructor(
    PULPInterface _pulp,
    ComptrollerInterface _unitroller,
    address[] memory _rewardTokens
  ) BoringOwnable() {
    rewardTokens = _rewardTokens;
    pulp = _pulp;
    ply = IERC20(pulp.PLY());
    unitroller = _unitroller;

    ply.approve(address(pulp), type(uint256).max);
  }

  /**
   * @dev Allow owner to withdraw only reward token
   */
  function ownerWithdraw(uint256 rewardTokenIndex, uint256 amount) external onlyOwner {
    require(rewardTokenIndex < rewardTokens.length, "invalid index");
    address rewardToken = rewardTokens[rewardTokenIndex];
    IERC20(rewardToken).safeTransfer(msg.sender, amount);
    emit RewardTokenWithdrawn(msg.sender, rewardToken, amount);
  }

  /**
   * @dev Add a new lp to the pool. Can only be called by the owner.
   * @param _stakeToken: token to be staked to the pool
   * @param _startTime: timestamp where the reward starts
   * @param _endTime: timestamp where the reward ends
   * @param _rewardPerSeconds: amount of reward token per second for the pool for each reward token
   */
  function addPool(
    address _stakeToken,
    uint32 _startTime,
    uint32 _endTime,
    uint256[] calldata _rewardPerSeconds
  ) external nonReentrant onlyOwner {
    require(!poolExists[_stakeToken], "add: duplicated pool");
    require(_stakeToken != address(0), "add: invalid stake token");
    require(rewardTokens.length == _rewardPerSeconds.length, "add: invalid length");

    require(_startTime > block.timestamp && _endTime > _startTime, "add: invalid times");

    poolInfo[poolLength].stakeToken = _stakeToken;
    poolInfo[poolLength].startTime = _startTime;
    poolInfo[poolLength].endTime = _endTime;
    poolInfo[poolLength].lastRewardTimestamp = _startTime;

    for (uint256 i = 0; i < _rewardPerSeconds.length; i++) {
      poolInfo[poolLength].poolRewardData[i] = PoolRewardData({
        rewardPerSecond: _rewardPerSeconds[i],
        accRewardPerShare: 0
      });
    }

    poolLength++;

    poolExists[_stakeToken] = true;

    emit AddNewPool(_stakeToken, _startTime, _endTime, _rewardPerSeconds);
  }

  /**
   * @dev Renew a pool to start another liquidity mining program
   * @param _pid: id of the pool to renew, must be pool that has not started or already ended
   * @param _startTime: timestamp where the reward starts
   * @param _endTime: timestamp where the reward ends
   * @param _rewardPerSeconds: amount of reward token per second for the pool
   *   0 if we want to stop the pool from accumulating rewards
   */
  function renewPool(
    uint256 _pid,
    uint32 _startTime,
    uint32 _endTime,
    uint256[] calldata _rewardPerSeconds
  ) external nonReentrant onlyOwner {
    _updatePoolRewards(_pid);

    PoolInfo storage pool = poolInfo[_pid];
    // check if pool has not started or already ended
    require(
      pool.startTime > block.timestamp || pool.endTime < block.timestamp,
      "renew: invalid pool state to renew"
    );
    // checking data of new pool
    require(rewardTokens.length == _rewardPerSeconds.length, "renew: invalid length");
    require(_startTime > block.timestamp && _endTime > _startTime, "renew: invalid times");

    pool.startTime = _startTime;
    pool.endTime = _endTime;
    pool.lastRewardTimestamp = _startTime;

    for (uint256 i = 0; i < _rewardPerSeconds.length; i++) {
      pool.poolRewardData[i].rewardPerSecond = _rewardPerSeconds[i];
    }

    emit RenewPool(_pid, _startTime, _endTime, _rewardPerSeconds);
  }

  /**
   * @dev Update a pool, allow to change end timestamp, reward per second
   * @param _pid: pool id to be renew
   * @param _endTime: timestamp where the reward ends
   * @param _rewardPerSeconds: amount of reward token per second for the pool,
   *   0 if we want to stop the pool from accumulating rewards
   */
  function updatePool(
    uint256 _pid,
    uint32 _endTime,
    uint256[] calldata _rewardPerSeconds
  ) external nonReentrant onlyOwner {
    _updatePoolRewards(_pid);

    PoolInfo storage pool = poolInfo[_pid];

    // should call renew pool if the pool has ended
    require(pool.endTime > block.timestamp, "update: pool already ended");
    require(rewardTokens.length == _rewardPerSeconds.length, "update: invalid length");
    require(_endTime > block.timestamp && _endTime > pool.startTime, "update: invalid end time");

    pool.endTime = _endTime;
    for (uint256 i = 0; i < _rewardPerSeconds.length; i++) {
      pool.poolRewardData[i].rewardPerSecond = _rewardPerSeconds[i];
    }

    emit UpdatePool(_pid, _endTime, _rewardPerSeconds);
  }

  /**
   * @dev Deposit tokens to accumulate rewards without harvesting
   * @param _pid: id of the pool
   * @param _amount: amount of stakeToken to be deposited
   */
  function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
    // update pool rewards, user's rewards
    _updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, false, 0);

    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    // collect stakeToken
    IERC20(pool.stakeToken).safeTransferFrom(msg.sender, address(this), _amount);

    // update user staked amount, and total staked amount for the pool
    user.amount = user.amount + _amount;
    pool.totalStake = pool.totalStake + _amount;

    emit Deposit(msg.sender, _pid, block.timestamp, _amount);
  }

  /**
   * @dev Withdraw token (of the sender) from pool without harvesting
   * @param _pid: id of the pool
   * @param _amount: amount of stakeToken to withdraw
   */
  function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
    _withdraw(_pid, _amount);
  }

  /**
   * @dev Withdraw all tokens (of the sender) from pool without harvesting
   * @param _pid: id of the pool
   */
  function withdrawAll(uint256 _pid) external nonReentrant {
    _withdraw(_pid, userInfo[_pid][msg.sender].amount);
  }

  /**
   * @notice EMERGENCY USAGE ONLY, USER'S REWARDS WILL BE RESET
   * @dev Emergency withdrawal function to allow withdraw all deposited tokens (of the sender)
   *   and reset all rewards
   * @param _pid: id of the pool
   */
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    uint256 amount = user.amount;

    user.amount = 0;
    uint256 rTokensLength = rewardTokens.length;
    for (uint256 i = 0; i < rTokensLength; i++) {
      UserRewardData storage rewardData = user.userRewardData[i];
      rewardData.lastRewardPerShare = 0;
      rewardData.unclaimedReward = 0;
    }

    pool.totalStake = pool.totalStake - amount;

    if (amount > 0) {
      IERC20(pool.stakeToken).safeTransfer(msg.sender, amount);
    }

    emit EmergencyWithdraw(msg.sender, _pid, block.timestamp, amount);
  }

  /**
   * @dev update rewards from multiple pools for the account
   */
  function updateMultiplePools(address account, uint256[] calldata _pids) external nonReentrant {
    uint256 pid;
    for (uint256 i = 0; i < _pids.length; i++) {
      pid = _pids[i];
      _updatePoolRewards(pid);
      // update user reward without harvesting
      _updateUserReward(account, pid, false, 0);
    }
  }

  /**
   * @dev Get pending rewards of a user from a pool, mostly for front-end
   * @param _pid: id of the pool
   * @param _user: user to check for pending rewards
   */
  function pendingRewards(uint256 _pid, address _user)
    external
    view
    returns (uint256[] memory rewards)
  {
    uint256 rTokensLength = rewardTokens.length;
    rewards = new uint256[](rTokensLength);
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 _totalStake = pool.totalStake;
    uint256 _poolLastRewardTimestamp = pool.lastRewardTimestamp;
    uint32 lastAccountedTime = _lastAccountedRewardTime(_pid);

    for (uint256 i = 0; i < rTokensLength; i++) {
      uint256 _accRewardPerShare = pool.poolRewardData[i].accRewardPerShare;
      if (lastAccountedTime > _poolLastRewardTimestamp && _totalStake != 0) {
        uint256 reward = (lastAccountedTime - _poolLastRewardTimestamp) *
          pool.poolRewardData[i].rewardPerSecond;
        _accRewardPerShare = _accRewardPerShare + ((reward * PRECISION) / _totalStake);
      }
      rewards[i] =
        (user.amount * (_accRewardPerShare - user.userRewardData[i].lastRewardPerShare)) /
        PRECISION;
      rewards[i] += user.userRewardData[i].unclaimedReward;
    }
  }

  /**
   * @dev Return list reward tokens
   */
  function getRewardTokens() external view returns (address[] memory) {
    return rewardTokens;
  }

  /**
   * @dev Return full details of a pool
   */
  function getPoolInfo(uint256 _pid)
    external
    view
    returns (
      uint256 totalStake,
      address stakeToken,
      uint32 startTime,
      uint32 endTime,
      uint32 lastRewardTimestamp,
      uint256[] memory rewardPerSeconds,
      uint256[] memory accRewardPerShares
    )
  {
    PoolInfo storage pool = poolInfo[_pid];
    (totalStake, stakeToken, startTime, endTime, lastRewardTimestamp) = (
      pool.totalStake,
      pool.stakeToken,
      pool.startTime,
      pool.endTime,
      pool.lastRewardTimestamp
    );
    uint256 rTokensLength = rewardTokens.length;
    rewardPerSeconds = new uint256[](rTokensLength);
    accRewardPerShares = new uint256[](rTokensLength);
    for (uint256 i = 0; i < rTokensLength; i++) {
      rewardPerSeconds[i] = pool.poolRewardData[i].rewardPerSecond;
      accRewardPerShares[i] = pool.poolRewardData[i].accRewardPerShare;
    }
  }

  /**
   * @dev Return user's info including deposited amount and reward data
   */
  function getUserInfo(uint256 _pid, address _account)
    public
    view
    returns (
      uint256 amount,
      uint256[] memory unclaimedRewards,
      uint256[] memory lastRewardPerShares
    )
  {
    UserInfo storage user = userInfo[_pid][_account];
    amount = user.amount;
    uint256 rTokensLength = rewardTokens.length;
    unclaimedRewards = new uint256[](rTokensLength);
    lastRewardPerShares = new uint256[](rTokensLength);
    for (uint256 i = 0; i < rTokensLength; i++) {
      unclaimedRewards[i] = user.userRewardData[i].unclaimedReward;
      lastRewardPerShares[i] = user.userRewardData[i].lastRewardPerShare;
    }
  }

  /**
   * @dev Return user's info including deposited amount and reward data
   */
  function updateAndGetUserInfo(uint256 _pid, address _account)
    external
    nonReentrant
    returns (
      uint256 amount,
      uint256[] memory unclaimedRewards,
      uint256[] memory lastRewardPerShares
    )
  {
    _updatePoolRewards(_pid);
    _updateUserReward(_account, _pid, false, 0);
    (amount, unclaimedRewards, lastRewardPerShares) = getUserInfo(_pid, _account);
  }

  /**
   * @dev Harvest rewards from a pool for an account. For all rewards that are not PLY, the entire amount will be
   transferred out. For PLY, it will follow the weekly locking schedule specified in PULP
   * @param _pid: id of the pool
   * @param _maxAmountOfPlyToHarvest: the maximum amount of Ply to harvest from the pool
   * @dev Note that only approved claimer can harvest & lock the rewards (check _doTransferOutRewards function)
   */
  function harvest(
    address account,
    uint256 _pid,
    uint256 _maxAmountOfPlyToHarvest
  ) external nonReentrant {
    _updatePoolRewards(_pid);
    _updateUserReward(account, _pid, true, _maxAmountOfPlyToHarvest);
  }

  /**
   * @dev Update rewards for one pool
   */
  function updatePoolRewards(uint256 _pid) external nonReentrant {
    _updatePoolRewards(_pid);
  }

  /**
   * @dev Update rewards for one pool
   */
  function _updatePoolRewards(uint256 _pid) internal {
    require(_pid < poolLength, "invalid pool id");
    PoolInfo storage pool = poolInfo[_pid];
    uint32 lastAccountedTime = _lastAccountedRewardTime(_pid);
    if (lastAccountedTime <= pool.lastRewardTimestamp) return;
    uint256 _totalStake = pool.totalStake;
    if (_totalStake == 0) {
      pool.lastRewardTimestamp = lastAccountedTime;
      return;
    }

    uint256 secondsElapsed = lastAccountedTime - pool.lastRewardTimestamp;
    uint256 rTokensLength = rewardTokens.length;
    for (uint256 i = 0; i < rTokensLength; i++) {
      PoolRewardData storage rewardData = pool.poolRewardData[i];
      uint256 reward = secondsElapsed * rewardData.rewardPerSecond;
      rewardData.accRewardPerShare =
        rewardData.accRewardPerShare +
        (reward * PRECISION) /
        _totalStake;
    }
    pool.lastRewardTimestamp = lastAccountedTime;
  }

  /**
   * @dev Withdraw _amount of stakeToken from pool _pid
   */
  function _withdraw(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "withdraw: insufficient amount");

    // update pool reward and harvest
    _updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, false, 0);

    user.amount = user.amount - _amount;
    pool.totalStake = pool.totalStake - _amount;

    IERC20(pool.stakeToken).safeTransfer(msg.sender, _amount);

    emit Withdraw(msg.sender, _pid, block.timestamp, _amount);
  }

  /**
   * @dev Update reward of _to address from pool _pid, harvest if needed
   */
  function _updateUserReward(
    address _to,
    uint256 _pid,
    bool doHarvest,
    uint256 _maxAmountOfPlyToHarvest
  ) internal {
    uint256 userAmount = userInfo[_pid][_to].amount;
    uint256 rTokensLength = rewardTokens.length;

    if (userAmount == 0) {
      // update user last reward per share to the latest pool reward per share
      // by right if user.amount is 0, user.unclaimedReward should be 0 as well,
      // except when user uses emergencyWithdraw function
      for (uint256 i = 0; i < rTokensLength; i++) {
        userInfo[_pid][_to].userRewardData[i].lastRewardPerShare = poolInfo[_pid]
          .poolRewardData[i]
          .accRewardPerShare;
      }
      return;
    }

    for (uint256 i = 0; i < rTokensLength; i++) {
      uint256 lastAccRewardPerShare = poolInfo[_pid].poolRewardData[i].accRewardPerShare;
      UserRewardData storage rewardData = userInfo[_pid][_to].userRewardData[i];
      // user's unclaim reward + user's amount * (pool's accRewardPerShare - user's lastRewardPerShare) / precision
      uint256 _pending = (userAmount * (lastAccRewardPerShare - rewardData.lastRewardPerShare)) /
        PRECISION;
      _pending = _pending + rewardData.unclaimedReward;

      rewardData.unclaimedReward = _pending;
      // update user last reward per share to the latest pool reward per share
      rewardData.lastRewardPerShare = lastAccRewardPerShare;

      if (doHarvest && _pending > 0) {
        uint256 harvestedAmount = _doTransferOutRewards(
          rewardData,
          IERC20(rewardTokens[i]),
          _to,
          _maxAmountOfPlyToHarvest
        );
        emit Harvest(_to, _pid, rewardTokens[i], harvestedAmount, block.timestamp);
      }
    }
  }

  /**
   * @dev Returns last accounted reward time, either the current timestamp or the endTime of the pool
   */
  function _lastAccountedRewardTime(uint256 _pid) internal view returns (uint32 _value) {
    _value = poolInfo[_pid].endTime;
    if (_value > block.timestamp) _value = block.timestamp.toUint32();
  }

  function _doTransferOutRewards(
    UserRewardData storage rewardData,
    IERC20 rewardToken,
    address _account,
    uint256 _maxAmountOfPlyToHarvest
  ) internal returns (uint256 harvestedAmount) {
    require(unitroller.isAllowedToClaimReward(_account, msg.sender), "not allowed to harvest");

    if (rewardToken == ply) {
      if (_maxAmountOfPlyToHarvest > 0) {
        harvestedAmount = Math.min(_maxAmountOfPlyToHarvest, rewardData.unclaimedReward);
        rewardData.unclaimedReward -= harvestedAmount;
        _lockPly(_account, harvestedAmount);
      }
    } else {
      harvestedAmount = rewardData.unclaimedReward;
      rewardData.unclaimedReward -= harvestedAmount;
      IERC20(rewardToken).safeTransfer(_account, harvestedAmount);
    }
  }

  function _lockPly(address _account, uint256 _amount) internal {
    (uint256 lockAmount, uint256 claimAmount) = pulp.calcLockAmount(_account, _amount);
    if (lockAmount != 0) {
      pulp.lockPly(_account, lockAmount);
    }
    if (claimAmount != 0) {
      ply.safeTransfer(_account, claimAmount);
    }
  }
}
