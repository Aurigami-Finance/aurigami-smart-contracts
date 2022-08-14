// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./BoringOwnableUpgradeable.sol";

contract ReferralDirectoryV2 is Initializable, BoringOwnableUpgradeable, UUPSUpgradeable {
  event NewReferralCode(bytes32 indexed code, address indexed user);
  event ReferralCodeUsed(bytes32 indexed code, address indexed user);
  event UserWhitelisted(address indexed user);

  mapping(address => bytes32) public userReferralCode;
  mapping(bytes32 => address) public referralCodeOwner;
  mapping(address => bytes32) public referralCodeUsed;
  mapping(address => uint256) public isUserWhitelisted;

  constructor() initializer {}

  function initialize() external initializer {
    __BoringOwnable_init();
  }

  /// @notice whitelists an address to create their referral code
  function whitelistUsers(address[] memory users) external onlyOwner {
    uint256 len = users.length;
    for (uint256 i = 0; i < len; i++) {
      isUserWhitelisted[users[i]] = 1;
      emit UserWhitelisted(users[i]);
    }
  }

  /// @notice called when an user creates his own referral code
  function registerNewUserReferralCode(bytes32 code) external {
    require(isUserWhitelisted[msg.sender] > 0, "user is not whitelisted");
    require(userReferralCode[msg.sender] == bytes32(0), "user has already had code");
    require(referralCodeOwner[code] == address(0), "code existed");

    userReferralCode[msg.sender] = code;
    referralCodeOwner[code] = msg.sender;

    emit NewReferralCode(code, msg.sender);
  }

  /// @notice called when an user confirms he is referred by a specified code
  function registerReferralCodeUsed(bytes32 code) external {
    require(referralCodeOwner[code] != address(0), "code not existed");
    require(referralCodeUsed[msg.sender] == bytes32(0), "already registered");

    referralCodeUsed[msg.sender] = code;

    emit ReferralCodeUsed(code, msg.sender);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
