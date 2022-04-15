pragma solidity 0.8.11;

import "./AuETH.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./AuriMathLib.sol";

contract EthRepayHelper {
  AuETH public immutable auETH;

  constructor(AuETH _auETH) {
    auETH = _auETH;
  }

  function repayBorrow() external payable {
    uint256 borrowAmount = Math.min(msg.value, auETH.borrowBalanceCurrent(msg.sender));
    auETH.repayBorrowBehalf{value: borrowAmount}(msg.sender);
    if (address(this).balance != 0) {
      Address.sendValue(payable(msg.sender), address(this).balance);
    }
  }

  receive() external payable {}
}
