pragma solidity ^0.8.11;

contract RNG {
  uint128 public jackpotNonce;
  uint128 public betNonce;

  /**
   * @notice generates a random seed
   * @dev https://github.com/aurora-is-near/aurora-engine/blob/0025328ba6c062af615669fe972c45f92d266894/etc/eth-contracts/contracts/test/Random.sol
   * @dev is technically a 256-bit RNG itself
   * but generates only one outcome for one block
   */
  function getRandomSeed() public returns (uint256) {
    bytes32[1] memory value;
    assembly {
      let ret := call(gas(), 0xc104f4840573bed437190daf5d2898c2bdf928ac, 0, 0, 0, value, 32)
    }
    return uint256(value[0]);
  }

  /**
   * @notice generates a random number in range [lo; hi)
   * @dev reverts if lo >= hi i.e. empty or invalid range
   * @dev the error in RNG uniformity should be negligibly small
   * unless hi-lo (the range length) is exceptionally high
   */
  function randRange(
    uint256 lo,
    uint256 hi,
    bool isJP
  ) internal returns (uint256) {
    require(hi > lo, "Invalid RNG range");

    uint256 seed = getRandomSeed();
    uint256 len = (hi - lo);
    uint256 nonce;
    if (isJP) {
      nonce = jackpotNonce;
      jackpotNonce += 1;
    } else {
      nonce = betNonce;
      betNonce += 1;
    }
    uint256 res = uint256(keccak256(abi.encode(seed, nonce))) % len;

    return res + lo;
  }
}
