// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

library Math {
  /**
   * @dev Returns the largest of two numbers.
   */
  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function max(
    uint256 a,
    uint256 b,
    uint256 c
  ) internal pure returns (uint256) {
    return max(a, max(b, c));
  }

  /**
   * @dev Returns the smallest of two numbers.
   */
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function min(
    uint256 a,
    uint256 b,
    uint256 c
  ) internal pure returns (uint256) {
    return min(min(a, b), c);
  }

  /**
   * @dev Returns the average of two numbers. The result is rounded towards
   * zero.
   */
  function average(uint256 a, uint256 b) internal pure returns (uint256) {
    // (a + b) / 2 can overflow.
    return (a & b) + (a ^ b) / 2;
  }

  /**
   * @dev Returns the ceiling of the division of two numbers.
   *
   * This differs from standard division with `/` in that it rounds up instead
   * of rounding down.
   */
  function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    // (a + b - 1) / b can overflow on addition, so we distribute.
    return a / b + (a % b == 0 ? 0 : 1);
  }

  /**
   * @dev Returns the abs of the difference of two numbers.
   */
  function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a > b) ? (a - b) : (b - a);
  }

  function safe216(uint256 n) internal pure returns (uint216) {
    require(n <= type(uint216).max, "safe216");
    return uint216(n);
  }

  function safe224(uint256 n) internal pure returns (uint224) {
    require(n <= type(uint224).max, "safe224");
    return uint224(n);
  }

  function safe32(uint256 n) internal pure returns (uint32) {
    require(n <= type(uint32).max, "safe32");
    return uint32(n);
  }
}
