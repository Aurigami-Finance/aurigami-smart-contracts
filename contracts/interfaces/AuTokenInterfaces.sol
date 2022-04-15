pragma solidity 0.8.11;

import "./ComptrollerInterface.sol";
import "./InterestRateModel.sol";
import "./EIP20NonStandardInterface.sol";
import "./EIP20Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AuTokenStorage is ReentrancyGuard {
    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 immutable public decimals;

    /**
     * @notice Maximum borrow rate that can ever be applied (.0005% / block)
     */

    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-auToken operations
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    InterestRateModel public interestRateModel;

    /**
     * @notice Initial exchange rate used when minting the first AuTokens (used when totalSupply = 0)
     */
    uint internal immutable initialExchangeRateMantissa;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint public reserveFactorMantissa;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint public accrualBlockTimestamp;

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    uint public borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint public totalBorrows;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint public totalSupply;

    /**
     * @notice Official record of token balances for each account
     */
    mapping (address => uint) internal accountTokens;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping (address => mapping (address => uint)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    /**
     * @notice Mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice Share of seized collateral that is added to reserves
     */
    uint public protocolSeizeShareMantissa;

    constructor(uint8 decimals_, uint256 initialExchangeRateMantissa_) ReentrancyGuard() {
        require(initialExchangeRateMantissa_ > 0, "initial exchange rate must be greater than zero.");
        decimals = decimals_;
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
    }
}

abstract contract AuTokenInterface is AuTokenStorage {
    /**
     * @notice Indicator that this is a AuToken contract (for inspection)
     */
    bool public constant isAuToken = true;


    /*** Market Events ***/

    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address auTokenCollateral, uint seizeTokens);


    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @notice Event emitted when the protocol seize share is changed
     */
    event NewProtocolSeizeShare(uint oldProtocolSeizeShareMantissa, uint newProtocolSeizeShareMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);


    /*** User Interface ***/

    function transfer(address dst, uint amount) external virtual returns (bool);
    function transferFrom(address src, address dst, uint amount) external virtual returns (bool);
    function approve(address spender, uint amount) external virtual returns (bool);
    function allowance(address owner, address spender) external virtual view returns (uint);
    function balanceOf(address owner) external virtual view returns (uint);
    function balanceOfUnderlying(address owner) external virtual returns (uint);
    function getAccountSnapshot(address account) external virtual view returns (uint, uint, uint);
    function borrowRatePerTimestamp() external virtual view returns (uint);
    function supplyRatePerTimestamp() external virtual view returns (uint);
    function totalBorrowsCurrent() external virtual returns (uint);
    function borrowBalanceCurrent(address account) external virtual returns (uint);
    function borrowBalanceStored(address account) public view virtual returns (uint);
    function exchangeRateCurrent() public virtual returns (uint);
    function exchangeRateStored() public view virtual returns (uint);
    function getBorrowDataOfAccount(address account) public view virtual returns (uint, uint);
    function getSupplyDataOfOneAccount(address account) public view virtual returns (uint, uint);
    function getSupplyDataOfTwoAccount(address account1, address account2) public view virtual returns (uint, uint, uint);
    function getCash() external virtual view returns (uint);
    function accrueInterest() public virtual;
    function seize(address liquidator, address borrower, uint seizeTokens) external virtual;


    /*** Admin Functions ***/

    function _setPendingAdmin(address payable newPendingAdmin) external virtual;
    function _acceptAdmin() external virtual;
    function _setComptroller(ComptrollerInterface newComptroller) public virtual;
    function _setReserveFactor(uint newReserveFactorMantissa) external virtual;
    function _reduceReserves(uint reduceAmount) external virtual;
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public virtual;
    function _setProtocolSeizeShare(uint newProtocolSeizeShareMantissa) external virtual;
}

contract AuErc20Storage {
    /**
     * @notice Underlying asset for this AuToken
     */
    address public immutable underlying;

    constructor(address underlying_) {
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply();
    }
}

abstract contract AuErc20Interface is AuErc20Storage {

    /*** User Interface ***/

    function mint(uint mintAmount) external virtual;
    function redeem(uint redeemTokens) external virtual;
    function redeemUnderlying(uint redeemAmount) external virtual;
    function borrow(uint borrowAmount) external virtual;
    function repayBorrow(uint repayAmount) external virtual;
    function repayBorrowBehalf(address borrower, uint repayAmount) external virtual;
    function liquidateBorrow(address borrower, uint repayAmount, AuTokenInterface auTokenCollateral) external virtual;
    function sweepToken(EIP20NonStandardInterface token) external virtual;

    /*** Admin Functions ***/

    function _addReserves(uint addAmount) external virtual;
}
