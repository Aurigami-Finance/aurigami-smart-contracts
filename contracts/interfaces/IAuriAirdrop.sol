// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;
pragma abicoder v2;

interface IAuriAirdrop {
  event DistributeToUser(
    bytes32 indexed campaignId,
    address indexed token,
    address indexed user,
    uint256 amountDistribute
  );

  event UnDistributeUser(
    bytes32 indexed campaignId,
    address indexed token,
    address indexed user,
    uint256 amountUnDistribute
  );

  event Redemption(
    bytes32 indexed campaignId,
    address indexed token,
    address indexed user,
    uint256 amount
  );

  function totalRewards(
    bytes32 campaignId,
    address token,
    address user
  ) external returns (uint256);

  function redeemedRewards(
    bytes32 campaignId,
    address token,
    address user
  ) external returns (uint256);

  function redeem(
    bytes32[] calldata campaignIds,
    address[] calldata tokens,
    address payable forAddr
  ) external returns (uint256[] memory amounts);

  function getRedeemableReward(
    bytes32 campaignId,
    address token,
    address user
  ) external view returns (uint256 amount);

  function readMultiple(
    bytes32[] calldata campaignIds,
    address[] calldata tokens,
    address user
  ) external view returns (uint256[] memory _totalRewards, uint256[] memory _redeemedRewards);
}
