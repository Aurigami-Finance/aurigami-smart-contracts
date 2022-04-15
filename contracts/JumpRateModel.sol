pragma solidity 0.8.11;

import "./interfaces/InterestRateModel.sol";

/**
  * @title Aurigami's JumpRateModel Contract
  * @author Aurigami
  */
contract JumpRateModel is InterestRateModel {
    event NewInterestParams(uint baseRatePerTimestamp, uint multiplierPerTimestamp, uint jumpMultiplierPerTimestamp, uint kink);

    /**
     * @notice The approximate number of timestamps per year that is assumed by the interest rate model
     */
    uint public constant timestampsPerYear = 31536000; // 1 year

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public immutable multiplierPerTimestamp;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public immutable baseRatePerTimestamp;

    /**
     * @notice The multiplierPerTimestamp after hitting a specified utilization point
     */
    uint public immutable jumpMultiplierPerTimestamp;

    /**
     * @notice The utilization point at which the jump multiplier is applied
     */
    uint public immutable kink;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerTimestamp after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    constructor(uint baseRatePerYear, uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_) {
        baseRatePerTimestamp = baseRatePerYear * 1e18 / timestampsPerYear / 1e18;
        multiplierPerTimestamp = multiplierPerYear * 1e18 / timestampsPerYear / 1e18;
        jumpMultiplierPerTimestamp = jumpMultiplierPerYear * 1e18 / timestampsPerYear / 1e18;
        kink = kink_;

        emit NewInterestParams(baseRatePerTimestamp, multiplierPerTimestamp, jumpMultiplierPerTimestamp, kink);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows * 1e18 / (cash + borrows - reserves);
    }

    /**
     * @notice Calculates the current borrow rate per timestmp
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per timestmp as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint cash, uint borrows, uint reserves) public override view returns (uint) {
        uint util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            return util * multiplierPerTimestamp / 1e18 + baseRatePerTimestamp;
        } else {
            uint normalRate = kink * multiplierPerTimestamp / 1e18 + baseRatePerTimestamp;
            uint excessUtil = util - kink;
            return excessUtil * jumpMultiplierPerTimestamp / 1e18 + normalRate;
        }
    }

    /**
     * @notice Calculates the current supply rate per timestmp
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per timestmp as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public override view returns (uint) {
        uint oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate * oneMinusReserveFactor / 1e18;
        return utilizationRate(cash, borrows, reserves) * rateToPool / 1e18;
    }
}
