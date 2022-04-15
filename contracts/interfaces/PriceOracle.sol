pragma solidity 0.8.11;

import "../AuToken.sol";


abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /**
      * @notice Get the underlying price of a AuToken asset
      * @param auToken The AuToken to get the underlying price of
      * @return The underlying asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getUnderlyingPrice(AuToken auToken) external view virtual returns (uint);

    function getUnderlyingPrices(AuToken[] calldata auTokens) external view virtual returns (uint256[] memory res);
}
