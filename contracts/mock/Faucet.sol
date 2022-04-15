pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Faucet is Ownable {
  uint256 public maxReceivedCount;

  address[] public testTokens;
  mapping(address => uint256) public dripAmounts;
  mapping(address => uint256) public receivedCount;

  struct TokenConfig {
    address token;
    uint256 dripAmount;
  }

  constructor() {}

  function fundToken(
    address token,
    uint256 dripAmount,
    uint256 initAmount
  ) public onlyOwner {
    if (initAmount > 0) IERC20(token).transferFrom(msg.sender, address(this), initAmount);
    dripAmounts[token] = dripAmount;
    for (uint8 i = 0; i < testTokens.length; ++i) {
      if (testTokens[i] == token) return;
    }
    testTokens.push(token);
  }

  function drip() public {
    require(receivedCount[msg.sender] <= maxReceivedCount, "User call drips too many times");
    for (uint256 i = 0; i < testTokens.length; i++) {
      IERC20(testTokens[i]).transfer(msg.sender, dripAmounts[testTokens[i]]);
    }
    receivedCount[msg.sender]++;
  }

  function setMaxReceivedCount(uint256 newVal) external onlyOwner {
    maxReceivedCount = newVal;
  }
}
