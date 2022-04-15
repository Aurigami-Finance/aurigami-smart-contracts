pragma solidity 0.8.11;

/**
 * @title Exponential module for storing fixed-precision decimals
 * @author Compound
 * @notice Exp is a struct which stores decimals with a fixed precision of 18 decimal places.
 *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
 *         `Exp({mantissa: 5100000000000000000})`.
 */
contract ExponentialNoError {
    type Exp is uint;
    type Double is uint;

    uint constant internal expScale = 1e18;
    uint constant internal doubleScale = 1e36;
    uint constant internal halfExpScale = expScale/2;
    uint constant internal mantissaOne = expScale;

    /**
     * @dev Truncates the given exp to a whole number value.
     *      For example, truncate(Exp{mantissa: 15 * expScale}) = 15
     */
    function truncate(Exp exp) pure internal returns (uint) {
        return Exp.unwrap(exp) / expScale;
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mul_ScalarTruncate(Exp a, uint scalar) pure internal returns (uint) {
        return truncate(mul_(a, scalar));
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function mul_ScalarTruncateAddUInt(Exp a, uint scalar, uint addend) pure internal returns (uint) {
        return truncate(mul_(a, scalar)) + addend;
    }

    /**
     * @dev Checks if first Exp is less than second Exp.
     */
    function lessThanExp(Exp left, Exp right) pure internal returns (bool) {
        return Exp.unwrap(left) < Exp.unwrap(right);
    }

    /**
     * @dev Checks if left Exp <= right Exp.
     */
    function lessThanOrEqualExp(Exp left, Exp right) pure internal returns (bool) {
        return Exp.unwrap(left) <= Exp.unwrap(right);
    }

    /**
     * @dev Checks if left Exp > right Exp.
     */
    function greaterThanExp(Exp left, Exp right) pure internal returns (bool) {
        return Exp.unwrap(left) > Exp.unwrap(right);
    }

    /**
     * @dev returns true if Exp is exactly zero
     */
    function isZeroExp(Exp value) pure internal returns (bool) {
        return Exp.unwrap(value) == 0;
    }

    function safe224(uint n) pure internal returns (uint224) {
        require(n <= type(uint224).max, "safe224");
        return uint224(n);
    }

    function add_(Exp a, Exp b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) + Exp.unwrap(b));
    }

    function add_(Double a, Double b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) + Double.unwrap(b));
    }

    function sub_(Exp a, Exp b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) - Exp.unwrap(b));
    }

    function sub_(Double a, Double b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) - Double.unwrap(b));
    }

    function mul_(Exp a, Exp b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) * Exp.unwrap(b) / expScale);
    }

    function mul_(Exp a, uint b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) * b);
    }

    function mul_(uint a, Exp b) pure internal returns (uint) {
        return a * Exp.unwrap(b) / expScale;
    }

    function mul_(Double a, Double b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) * Double.unwrap(b) / doubleScale);
    }

    function mul_(Double a, uint b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) * b);
    }

    function mul_(uint a, Double b) pure internal returns (uint) {
        return a * Double.unwrap(b) / doubleScale;
    }

    function div_(Exp a, Exp b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) * expScale / Exp.unwrap(b));
    }

    function div_(Exp a, uint b) pure internal returns (Exp) {
        return Exp.wrap(Exp.unwrap(a) / b);
    }

    function div_(uint a, Exp b) pure internal returns (uint) {
        return a * expScale / Exp.unwrap(b);
    }

    function div_(Double a, Double b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) * doubleScale / Double.unwrap(b));
    }

    function div_(Double a, uint b) pure internal returns (Double) {
        return Double.wrap(Double.unwrap(a) / b);
    }

    function div_(uint a, Double b) pure internal returns (uint) {
        return a * doubleScale / Double.unwrap(b);
    }

    function fraction(uint a, uint b) pure internal returns (Double) {
        return Double.wrap(a * doubleScale / b);
    }
}
