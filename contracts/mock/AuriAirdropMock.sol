// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../BoringOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/IAuriAirdrop.sol";

contract AuriAirdropMock is
  IAuriAirdrop,
  Initializable,
  ReentrancyGuardUpgradeable,
  BoringOwnableUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  // campaignId => token => user => amount
  mapping(bytes32 => mapping(address => mapping(address => uint256))) public totalRewards;

  // campaignId => token => user => amount
  mapping(bytes32 => mapping(address => mapping(address => uint256))) public redeemedRewards;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize() external initializer {
    __ReentrancyGuard_init();
    __BoringOwnable_init();
  }

  function distribute(
    bytes32 campaignId,
    address token,
    address[] calldata users,
    uint256[] calldata amounts
  ) external payable onlyOwner {
    require(users.length == amounts.length, "invalid array");

    uint256 total;
    for (uint256 i = 0; i < users.length; i++) {
      totalRewards[campaignId][token][users[i]] += amounts[i];
      total += amounts[i];

      emit DistributeToUser(campaignId, token, users[i], amounts[i]);
    }

    _pullToken(token, total);
  }

  function unDistribute(
    bytes32 campaignId,
    address token,
    address[] calldata users
  ) external onlyOwner {
    uint256 total;

    for (uint256 i = 0; i < users.length; i++) {
      uint256 unredeemedAmount = getRedeemableReward(campaignId, token, users[i]);
      totalRewards[campaignId][token][users[i]] -= unredeemedAmount;
      total += unredeemedAmount;

      emit UnDistributeUser(campaignId, token, users[i], unredeemedAmount);
    }
    _pushToken(token, total, payable(owner));
  }

  function redeem(
    bytes32[] calldata campaignIds,
    address[] calldata tokens,
    address payable user
  ) external nonReentrant returns (uint256[] memory amounts) {
    require(campaignIds.length == tokens.length, "invalid arrays");

    amounts = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      amounts[i] = getRedeemableReward(campaignIds[i], tokens[i], user);
      redeemedRewards[campaignIds[i]][tokens[i]][user] += amounts[i];
      _pushToken(tokens[i], amounts[i], user);

      emit Redemption(campaignIds[i], tokens[i], user, amounts[i]);
    }
  }

  function getRedeemableReward(
    bytes32 campaignId,
    address token,
    address user
  ) public view returns (uint256 amount) {
    amount = totalRewards[campaignId][token][user] - redeemedRewards[campaignId][token][user];
  }

  function readMultiple(
    bytes32[] calldata campaignIds,
    address[] calldata tokens,
    address user
  ) external view returns (uint256[] memory _totalRewards, uint256[] memory _redeemedRewards) {
    _totalRewards = new uint256[](tokens.length);
    _redeemedRewards = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      _totalRewards[i] = totalRewards[campaignIds[i]][tokens[i]][user];
      _redeemedRewards[i] = redeemedRewards[campaignIds[i]][tokens[i]][user];
    }
  }

  function dummyV2(
    bytes32 campaignId,
    address token,
    address user
  ) public view returns (uint256 amount) {
    amount = totalRewards[campaignId][token][user] - redeemedRewards[campaignId][token][user];
  }

  function _pullToken(address token, uint256 amount) internal {
    if (amount == 0) return;
    if (token == ETH_ADDRESS) require(msg.value == amount, "ETH_AMOUNT_MISMATCH");
    else IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
  }

  function _pushToken(
    address token,
    uint256 amount,
    address payable to
  ) internal {
    if (amount == 0) return;
    if (token == ETH_ADDRESS) AddressUpgradeable.sendValue(to, amount);
    else IERC20Upgradeable(token).safeTransfer(to, amount);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
