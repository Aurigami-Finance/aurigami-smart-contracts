pragma solidity 0.8.11;

import "./ExponentialNoError.sol";

/**
 * @title Exponential module for storing fixed-precision decimals
 * @notice Exp is a user-defined type which stores decimals with a fixed precision of 18 decimal places.
 *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
 *         `Exp.wrap(5100000000000000000)`.


 * @notice All the Math errors were removed from this contract. Every math error will now cause the transaction to be reverted.
 */
contract Exponential is ExponentialNoError {
    /**
     * @dev Creates an exponential from numerator and denominator values.
     */
    function getExp(uint num, uint denom) pure internal returns (Exp) {
        return Exp.wrap(num * expScale / denom);
    }

    /**
     * @dev Multiply an Exp by a scalar, returning a new Exp.
     */
    function mulScalar(Exp a, uint scalar) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) * scalar);
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mulScalarTruncate(Exp a, uint scalar) pure internal returns (uint) {
        return truncate(mulScalar(a, scalar));
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function mulScalarTruncateAddUInt(Exp a, uint scalar, uint addend) pure internal returns (uint) {
        return truncate(mulScalar(a, scalar)) + addend;
    }

    /**
     * @dev Divide an Exp by a scalar, returning a new Exp.
     */
    function divScalar(Exp a, uint scalar) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) / scalar);
    }

    /**
     * @dev Divide a scalar by an Exp, returning a new Exp.
     */
    function divScalarByExp(uint scalar, Exp divisor) pure internal returns (Exp) {
        /*
          We are doing this as:
          getExp(expScale * scalar, divisor)
          How it works:
          Exp = a / b;
          Scalar = s;
          `s / (a / b)` = `b * s / a` and since for an Exp `a = mantissa, b = expScale`
        */
        return getExp(expScale * scalar, Exp.unwrap(divisor));
    }

    /**
     * @dev Divide a scalar by an Exp, then truncate to return an unsigned integer.
     */
    function divScalarByExpTruncate(uint scalar, Exp divisor) pure internal returns (uint) {
        return truncate(divScalarByExp(scalar, divisor));
    }

    /**
     * @dev Multiplies two exponentials, returning a new exponential.
     */
    function mulExp(Exp a, Exp b) pure internal returns (Exp) {

        uint doubleScaledProduct = Exp.unwrap(a) * Exp.unwrap(b);

        // We add half the scale before dividing so that we get rounding instead of truncation.
        //  See "Listing 6" and text above it at https://accu.org/index.php/journals/1717
        // Without this change, a result like 6.6...e-19 will be truncated to 0 instead of being rounded to 1e-18.
        uint doubleScaledProductWithHalfScale = halfExpScale + doubleScaledProduct;

        uint product = doubleScaledProductWithHalfScale / expScale;

        return Exp.wrap(product);
    }

    /**
     * @dev Multiplies two exponentials given their mantissas, returning a new exponential.
     */
    function mulExp(uint a, uint b) pure internal returns (Exp) {
        return mulExp(Exp.wrap(a), Exp.wrap(b));
    }

    /**
     * @dev Multiplies three exponentials, returning a new exponential.
     */
    function mulExp3(Exp a, Exp b, Exp c) pure internal returns (Exp) {
        return mulExp(mulExp(a, b), c);
    }

    /**
     * @dev Divides two exponentials, returning a new exponential.
     *     (a/scale) / (b/scale) = (a/scale) * (scale/b) = a/b,
     *  which we can scale as an Exp by calling getExp(a.mantissa, b.mantissa)
     */
    function divExp(Exp a, Exp b) pure internal returns (Exp) {
        return getExp(Exp.unwrap(a), Exp.unwrap(b));
    }
}
