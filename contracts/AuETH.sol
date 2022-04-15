pragma solidity 0.8.11;

import "./AuToken.sol";

contract AuETH is AuToken {
  /**
   * @notice Construct a new AuETH money market
   * @param comptroller_ The address of the Comptroller
   * @param interestRateModel_ The address of the interest rate model
   * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
   * @param name_ ERC-20 name of this token
   * @param symbol_ ERC-20 symbol of this token
   * @param decimals_ ERC-20 decimal precision of this token
   * @param admin_ Address of the administrator of this token
   */
  constructor(
    ComptrollerInterface comptroller_,
    InterestRateModel interestRateModel_,
    uint initialExchangeRateMantissa_,
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address payable admin_
  )  AuToken(
      comptroller_,
      interestRateModel_,
      initialExchangeRateMantissa_,
      name_,
      symbol_,
      decimals_,
      admin_
    ) {}

  /*** User Interface ***/

  /**
   * @notice Sender supplies assets into the market and receives auTokens in exchange
   * @dev Reverts upon any failure
   */
  function mint() external payable {
    mintInternal(msg.value);
  }

  /**
   * @notice Sender redeems auTokens in exchange for the underlying asset
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param redeemTokens The number of auTokens to redeem into underlying
   */
  function redeem(uint256 redeemTokens) external {
    redeemInternal(redeemTokens);
  }

  /**
   * @notice Sender redeems auTokens in exchange for a specified amount of underlying asset
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param redeemAmount The amount of underlying to redeem
   */
  function redeemUnderlying(uint256 redeemAmount) external {
    redeemUnderlyingInternal(redeemAmount);
  }

  /**
   * @notice Sender borrows assets from the protocol to their own address
   * @param borrowAmount The amount of the underlying asset to borrow
   */
  function borrow(uint256 borrowAmount) external {
    borrowInternal(borrowAmount);
  }

  /**
   * @notice Sender repays their own borrow
   * @dev Reverts upon any failure
   */
  function repayBorrow() external payable {
    repayBorrowInternal(msg.value);
  }

  /**
   * @notice Sender repays a borrow belonging to borrower
   * @dev Reverts upon any failure
   * @param borrower the account with the debt being payed off
   */
  function repayBorrowBehalf(address borrower) external payable {
    repayBorrowBehalfInternal(borrower, msg.value);
  }

  /**
   * @notice The sender liquidates the borrowers collateral.
   *  The collateral seized is transferred to the liquidator.
   * @dev Reverts upon any failure
   * @param borrower The borrower of this auToken to be liquidated
   * @param auTokenCollateral The market in which to seize collateral from the borrower
   */
  function liquidateBorrow(address borrower, AuToken auTokenCollateral) external payable {
    liquidateBorrowInternal(borrower, msg.value, auTokenCollateral);
  }

  /**
   * @notice The sender adds to reserves.
   */
  function _addReserves() external payable {
    _addReservesInternal(msg.value);
  }

  /**
   * @notice Send Ether to AuETH to mint
   */
  fallback() external payable {
    mintInternal(msg.value);
  }

  /*** Safe Token ***/

  /**
   * @notice Gets balance of this contract in terms of Ether, before this message
   * @dev This excludes the value of the current message, if any
   * @return The quantity of Ether owned by this contract
   */
  function getCashPrior() internal view override returns (uint256) {
    uint256 startingBalance = address(this).balance - msg.value;
    return startingBalance;
  }

  /**
   * @notice Perform the actual transfer in, which is a no-op
   * @param from Address sending the Ether
   * @param amount Amount of Ether being sent
   * @return The actual amount of Ether transferred
   */
  function doTransferIn(address from, uint256 amount) internal override returns (uint256) {
    // Sanity checks
    require(msg.sender == from, "sender mismatch");
    require(msg.value == amount, "value mismatch");
    return amount;
  }

  function doTransferOut(address payable to, uint256 amount) internal override {
    /* Send the Ether, with minimal gas and revert on failure */
    to.transfer(amount);
  }
}
