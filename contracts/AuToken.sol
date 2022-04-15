pragma solidity 0.8.11;

import "./interfaces/ComptrollerInterface.sol";
import "./interfaces/AuTokenInterfaces.sol";
import "./Exponential.sol";
import "./interfaces/EIP20Interface.sol";
import "./interfaces/InterestRateModel.sol";

/**
 * @title Aurigami Finance's AuToken Contract
 * @notice Abstract base for auTokens
 */
abstract contract AuToken is AuTokenInterface, Exponential {
    error MarketNotFresh();
    error TokenInsufficientCash();
    error Unauthorized();
    error BadInput();
    error InvalidCloseAmountRequested();
    error InvalidAccountPair();

    constructor(
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address admin_
    ) AuTokenStorage(decimals_, initialExchangeRateMantissa_) {
        // set admin temporarily
        admin = payable(msg.sender);

        // Set the comptroller
        _setComptroller(comptroller_);

        // Initialize block timestamp and borrow index (block timestamp mocks depend on comptroller being set)
        accrualBlockTimestamp = getBlockTimestamp();
        borrowIndex = mantissaOne;

        // Set the interest rate model (depends on block timestamp / borrow index)
        _setInterestRateModelFresh(interestRateModel_);

        name = name_;
        symbol = symbol_;

        admin = payable(admin_);
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     */
    function transferTokens(address spender, address src, address dst, uint tokens) internal {
        /* Fail if transfer not allowed */
        comptroller.transferAllowed(address(this), src, dst, tokens);

        /* Do not allow self-transfers */
        if (src == dst) {
            revert BadInput();
        }

        /* Get the allowance, infinite for the account owner */
        uint startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        uint allowanceNew;
        uint srcTokensNew;
        uint dstTokensNew;

        allowanceNew = startingAllowance - tokens;
        srcTokensNew = accountTokens[src] - tokens;
        dstTokensNew = accountTokens[dst] + tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[src] = srcTokensNew;
        accountTokens[dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != type(uint256).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);

        // unused function
        // comptroller.transferVerify(address(this), src, dst, tokens);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, src, dst, amount);
        return true;
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        address src = msg.sender;
        transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view override returns (uint256) {
        return accountTokens[owner];
    }

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) external override returns (uint) {
        Exp exchangeRate = Exp.wrap(exchangeRateCurrent());
        uint balance = mulScalarTruncate(exchangeRate, accountTokens[owner]);
        return balance;
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account) external view override returns (uint, uint, uint) {
        uint auTokenBalance = accountTokens[account];

        uint borrowBalance = borrowBalanceStoredInternal(account);

        uint exchangeRateMantissa = exchangeRateStoredInternal();

        return (auTokenBalance, borrowBalance, exchangeRateMantissa);
    }

    /**
     * @dev Function to simply retrieve block timestamp
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function getBlockTimestamp() internal view returns (uint) {
        return block.timestamp;
    }

    /**
     * @notice Returns the current per-timestamp borrow interest rate for this auToken
     * @return The borrow interest rate per timestmp, scaled by 1e18
     */
    function borrowRatePerTimestamp() external view override returns (uint) {
        return interestRateModel.getBorrowRate(getCashPrior(), totalBorrows, totalReserves);
    }

    /**
     * @notice Returns the current per-timestamp supply interest rate for this auToken
     * @return The supply interest rate per timestmp, scaled by 1e18
     */
    function supplyRatePerTimestamp() external view override returns (uint) {
        return interestRateModel.getSupplyRate(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    }

    /**
     * @notice Returns the current total borrows plus accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent() external override nonReentrant returns (uint) {
        accrueInterest();
        return totalBorrows;
    }

    /**
     * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance using the updated borrowIndex
     * @param account The address whose balance should be calculated after updating borrowIndex
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account) external override nonReentrant returns (uint) {
        accrueInterest();
        return borrowBalanceStored(account);
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account) public view override returns (uint) {
        uint result = borrowBalanceStoredInternal(account);
        return result;
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return the calculated balance
     */
    function borrowBalanceStoredInternal(address account) internal view returns (uint) {
        uint principalTimesIndex;
        uint result;

        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0){
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        principalTimesIndex = borrowSnapshot.principal * borrowIndex;

        result = principalTimesIndex / borrowSnapshot.interestIndex;

        return result;
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() public override nonReentrant returns (uint) {
        accrueInterest();
        return exchangeRateStored();
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the AuToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() public view override returns (uint) {
        return exchangeRateStoredInternal();
    }

    /**
     * @notice Retrieve the totalBorrows & borrowBalance of account
     * @param account The address whose data to be retrieved
     * @return (totalBorrows, borrowBalance of account)
     */
    function getBorrowDataOfAccount(address account) public view override returns (uint, uint) {
        return (totalBorrows, borrowBalanceStored(account));
    }

    /**
     * @notice Retrieve the totalSupply & auTokenBalance of account
     * @param account The address whose data to be retrieved
     * @return (totalSupply, auTokenBalance of account)
     */
    function getSupplyDataOfOneAccount(address account) public view override returns (uint, uint) {
        return (totalSupply, accountTokens[account]);
    }

    /**
     * @notice Retrieve the totalSupply & auTokenBalance of two accounts
     * @param account1 The address whose data to be retrieved
     * @param account2 The address whose data to be retrieved
     * @return (totalSupply, auTokenBalance of account1, auTokenBalance of account2)
     */
    function getSupplyDataOfTwoAccount(address account1, address account2) public view override returns (uint, uint, uint) {
        return (totalSupply, accountTokens[account1], accountTokens[account2]);
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the AuToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return (calculated exchange rate scaled by 1e18)
     */
    function exchangeRateStoredInternal() internal view returns (uint) {
        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint totalCash = getCashPrior();
            uint cashPlusBorrowsMinusReserves;
            Exp exchangeRate;

            cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;

            exchangeRate = getExp(cashPlusBorrowsMinusReserves, _totalSupply);

            return Exp.unwrap(exchangeRate);
        }
    }

    /**
     * @notice Get cash balance of this auToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view override returns (uint) {
        return getCashPrior();
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public override{
        /* Remember the initial block timestamp */
        uint currentBlockTimestamp = getBlockTimestamp();
        uint accrualBlockTimestampPrior = accrualBlockTimestamp;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockTimestampPrior == currentBlockTimestamp){
            return;
        }

        /* Read the previous values out of storage */
        uint cashPrior = getCashPrior();
        uint borrowsPrior = totalBorrows;
        uint reservesPrior = totalReserves;
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
        require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

        /* Calculate the number of timestamp elapsed since the last accrual */
        uint timestampDelta = currentBlockTimestamp - accrualBlockTimestampPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * timestampDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        Exp simpleInterestFactor;
        uint interestAccumulated;
        uint totalBorrowsNew;
        uint totalReservesNew;
        uint borrowIndexNew;

        simpleInterestFactor = mulScalar(Exp.wrap(borrowRateMantissa), timestampDelta);

        interestAccumulated = mulScalarTruncate(simpleInterestFactor, borrowsPrior);

        totalBorrowsNew = interestAccumulated + borrowsPrior;

        totalReservesNew = mulScalarTruncateAddUInt(Exp.wrap(reserveFactorMantissa), interestAccumulated, reservesPrior);

        borrowIndexNew = mulScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockTimestamp = currentBlockTimestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);

    }

    /**
     * @notice Sender supplies assets into the market and receives auTokens in exchange
     * @param mintAmount The amount of the underlying asset to supply
     * @return the actual mint amount.
     */
    function mintInternal(uint mintAmount) internal nonReentrant returns (uint) {
        accrueInterest();
        return mintFresh(msg.sender, mintAmount);
    }

    struct MintLocalVars {
        uint exchangeRateMantissa;
        uint mintTokens;
        uint totalSupplyNew;
        uint accountTokensNew;
        uint actualMintAmount;
    }

    /**
     * @notice User supplies assets into the market and receives auTokens in exchange
     * @dev Assumes interest has already been accrued up to the current block
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @return the actual mint amount.
     */
    function mintFresh(address minter, uint mintAmount) internal returns (uint) {
        /* Fail if mint not allowed */
        comptroller.mintAllowed(address(this), minter, mintAmount);

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }
        MintLocalVars memory vars;

        vars.exchangeRateMantissa = exchangeRateStoredInternal();

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `doTransferIn` for the minter and the mintAmount.
         *  Note: The auToken must handle variations between ERC-20 and ETH underlying.
         *  `doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the auToken holds an additional `actualMintAmount`
         *  of cash.
         */
        vars.actualMintAmount = doTransferIn(minter, mintAmount);

        /*
         * We get the current exchange rate and calculate the number of auTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        vars.mintTokens = divScalarByExpTruncate(vars.actualMintAmount, Exp.wrap(vars.exchangeRateMantissa));

        /*
         * We calculate the new total supply of auTokens and minter token balance, checking for overflow:
         *  totalSupplyNew = totalSupply + mintTokens
         *  accountTokensNew = accountTokens[minter] + mintTokens
         */
        vars.totalSupplyNew = totalSupply + vars.mintTokens;

        vars.accountTokensNew = accountTokens[minter] + vars.mintTokens;

        /* We write previously calculated values into storage */
        totalSupply = vars.totalSupplyNew;
        accountTokens[minter] = vars.accountTokensNew;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
        emit Transfer(address(this), minter, vars.mintTokens);

        /* We call the defense hook */
        // unused function
        // comptroller.mintVerify(address(this), minter, vars.actualMintAmount, vars.mintTokens);

        return vars.actualMintAmount;
    }

    /**
     * @notice Sender redeems auTokens in exchange for the underlying asset
     * @param redeemTokens The number of auTokens to redeem into underlying
     */
    function redeemInternal(uint redeemTokens) internal nonReentrant {
        accrueInterest();
        redeemFresh(payable(msg.sender), redeemTokens, 0);
    }

    /**
     * @notice Sender redeems auTokens in exchange for a specified amount of underlying asset
     * @param redeemAmount The amount of underlying to receive from redeeming auTokens
     */
    function redeemUnderlyingInternal(uint redeemAmount) internal nonReentrant {
        accrueInterest();
        redeemFresh(payable(msg.sender), 0, redeemAmount);
    }

    struct RedeemLocalVars {
        uint exchangeRateMantissa;
        uint redeemTokens;
        uint redeemAmount;
        uint totalSupplyNew;
        uint accountTokensNew;
    }

    /**
     * @notice User redeems auTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemTokensIn The number of auTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming auTokens (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     */
    function redeemFresh(address payable redeemer, uint redeemTokensIn, uint redeemAmountIn) internal{
        require(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

        RedeemLocalVars memory vars;

        /* exchangeRate = invoke Exchange Rate Stored() */
        vars.exchangeRateMantissa = exchangeRateStoredInternal();

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            if (redeemTokensIn == type(uint256).max) {
                vars.redeemTokens = accountTokens[redeemer];
            } else {
                vars.redeemTokens = redeemTokensIn;
            }

            vars.redeemAmount = mulScalarTruncate(Exp.wrap(vars.exchangeRateMantissa), vars.redeemTokens);
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            if (redeemAmountIn == type(uint256).max) {
                vars.redeemTokens = accountTokens[redeemer];

                vars.redeemAmount = mulScalarTruncate(Exp.wrap(vars.exchangeRateMantissa), vars.redeemTokens);
            } else {
                vars.redeemAmount = redeemAmountIn;

                vars.redeemTokens = divScalarByExpTruncate(redeemAmountIn, Exp.wrap(vars.exchangeRateMantissa));
            }
        }

        /* Fail if redeem not allowed */
        comptroller.redeemAllowed(address(this), redeemer, vars.redeemTokens);

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        /*
         * We calculate the new total supply and redeemer balance, checking for underflow:
         *  totalSupplyNew = totalSupply - redeemTokens
         *  accountTokensNew = accountTokens[redeemer] - redeemTokens
         */
        vars.totalSupplyNew = totalSupply - vars.redeemTokens;
        vars.accountTokensNew = accountTokens[redeemer] - vars.redeemTokens;

        /* Revert if protocol has insufficient cash */
        if (getCashPrior() < vars.redeemAmount) {
            revert TokenInsufficientCash();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write previously calculated values into storage */
        totalSupply = vars.totalSupplyNew;
        accountTokens[redeemer] = vars.accountTokensNew;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), vars.redeemTokens);
        emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);

        // the comptroller's redeemVerify hook is inlined in here to save external call
        if (vars.redeemTokens == 0 && vars.redeemAmount > 0) {
            revert("redeemTokens zero");
        }

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  Note: The auToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the auToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  Note: This doTransferOut is moved here to prevent exploits similar to the CREAM hack.
         */
        doTransferOut(redeemer, vars.redeemAmount);
    }

    /**
      * @notice Sender borrows assets from the protocol to their own address
      * @param borrowAmount The amount of the underlying asset to borrow
      */
    function borrowInternal(uint borrowAmount) internal nonReentrant {
        accrueInterest();
        borrowFresh(payable(msg.sender), borrowAmount);
    }

    struct BorrowLocalVars {
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
    }

    /**
      * @notice Users borrow assets from the protocol to their own address
      * @param borrowAmount The amount of the underlying asset to borrow
      */
    function borrowFresh(address payable borrower, uint borrowAmount) internal {
        /* Fail if borrow not allowed */
        comptroller.borrowAllowed(address(this), borrower, borrowAmount);

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        /* Revert if protocol has insufficient underlying cash */
        if (getCashPrior() < borrowAmount) {
            revert TokenInsufficientCash();
        }

        BorrowLocalVars memory vars;

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowsNew = accountBorrows + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        vars.accountBorrows = borrowBalanceStoredInternal(borrower);

        vars.accountBorrowsNew = vars.accountBorrows + borrowAmount;

        vars.totalBorrowsNew = totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        // unused function
        // comptroller.borrowVerify(address(this), borrower, borrowAmount);

        /*
         * We invoke doTransferOut for the borrower and the borrowAmount.
         *  Note: The auToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the auToken borrowAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  Note: This doTransferOut is moved here to prevent exploits similar to the CREAM hack.
         */
        doTransferOut(borrower, borrowAmount);

    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return the actual repayment amount.
     */
    function repayBorrowInternal(uint repayAmount) internal nonReentrant returns (uint) {
        accrueInterest();
        return repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return the actual repayment amount.
     */
    function repayBorrowBehalfInternal(address borrower, uint repayAmount) internal nonReentrant returns (uint) {
        accrueInterest();
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    struct RepayBorrowLocalVars {
        uint repayAmount;
        uint borrowerIndex;
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
        uint actualRepayAmount;
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of undelrying tokens being returned
     * @return the actual repayment amount.
     */
    function repayBorrowFresh(address payer, address borrower, uint repayAmount) internal returns (uint) {
        /* Fail if repayBorrow not allowed */
        comptroller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }
        RepayBorrowLocalVars memory vars;

        /* We remember the original borrowerIndex for verification purposes */
        vars.borrowerIndex = accountBorrows[borrower].interestIndex;

        /* We fetch the amount the borrower owes, with accumulated interest */
        vars.accountBorrows = borrowBalanceStoredInternal(borrower);

        /* If repayAmount == type(uint256).max, repayAmount = accountBorrows */
        if (repayAmount == type(uint256).max) {
            vars.repayAmount = vars.accountBorrows;
        } else {
            vars.repayAmount = repayAmount;
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  Note: The auToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the auToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        vars.accountBorrowsNew = vars.accountBorrows - vars.actualRepayAmount;

        vars.totalBorrowsNew = totalBorrows - vars.actualRepayAmount;

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(payer, borrower, vars.actualRepayAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        // unused function
        // comptroller.repayBorrowVerify(address(this), payer, borrower, vars.actualRepayAmount, vars.borrowerIndex);

        return vars.actualRepayAmount;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this auToken to be liquidated
     * @param auTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowInternal(address borrower, uint repayAmount, AuTokenInterface auTokenCollateral) internal nonReentrant returns (uint) {
        accrueInterest();
        auTokenCollateral.accrueInterest();
        return liquidateBorrowFresh(msg.sender, borrower, repayAmount, auTokenCollateral);
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this auToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param auTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowFresh(address liquidator, address borrower, uint repayAmount, AuTokenInterface auTokenCollateral) internal returns (uint) {
        /* Fail if liquidate not allowed */
        comptroller.liquidateBorrowAllowed(address(this), address(auTokenCollateral), liquidator, borrower, repayAmount);
        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        /* Verify auTokenCollateral market's block timestamp equals current block timestamp */
        if (auTokenCollateral.accrualBlockTimestamp() != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            revert InvalidAccountPair();
        }

        /* Fail if repayAmount = 0 */
        if (repayAmount == 0) {
            revert InvalidCloseAmountRequested();
        }

        /* Fail if repayAmount = type(uint256).max */
        if (repayAmount == type(uint256).max) {
            revert InvalidCloseAmountRequested();
        }


        /* Fail if repayBorrow fails */
        uint actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        uint seizeTokens = comptroller.liquidateCalculateSeizeTokens(address(this), address(auTokenCollateral), actualRepayAmount);

        /* Revert if borrower collateral token balance < seizeTokens */
        require(auTokenCollateral.balanceOf(borrower) >= seizeTokens, "LIQUIDATE_SEIZE_TOO_MUCH");

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        if (address(auTokenCollateral) == address(this)) {
            seizeInternal(address(this), liquidator, borrower, seizeTokens);
        } else {
            auTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(liquidator, borrower, actualRepayAmount, address(auTokenCollateral), seizeTokens);

        /* We call the defense hook */
        // unused function
        // comptroller.liquidateBorrowVerify(address(this), address(auTokenCollateral), liquidator, borrower, actualRepayAmount, seizeTokens);

        return actualRepayAmount;
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another auToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed auToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of auTokens to seize
     */
    function seize(address liquidator, address borrower, uint seizeTokens) external override nonReentrant {
        seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    struct SeizeInternalLocalVars {
        uint borrowerTokensNew;
        uint liquidatorTokensNew;
        uint liquidatorSeizeTokens;
        uint protocolSeizeTokens;
        uint protocolSeizeAmount;
        uint exchangeRateMantissa;
        uint totalReservesNew;
        uint totalSupplyNew;
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another AuToken.
     *  Its absolutely critical to use msg.sender as the seizer auToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed auToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of auTokens to seize
     */
    function seizeInternal(address seizerToken, address liquidator, address borrower, uint seizeTokens) internal{
        /* Fail if seize not allowed */
        comptroller.seizeAllowed(address(this), seizerToken, liquidator, borrower, seizeTokens);

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            revert InvalidAccountPair();
        }

        SeizeInternalLocalVars memory vars;

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        vars.borrowerTokensNew = accountTokens[borrower] - seizeTokens;

        vars.protocolSeizeTokens = mul_(seizeTokens, Exp.wrap(protocolSeizeShareMantissa));
        vars.liquidatorSeizeTokens = seizeTokens - vars.protocolSeizeTokens;

        vars.exchangeRateMantissa = exchangeRateStoredInternal();

        vars.protocolSeizeAmount = mul_ScalarTruncate(Exp.wrap(vars.exchangeRateMantissa), vars.protocolSeizeTokens);

        vars.totalReservesNew = totalReserves + vars.protocolSeizeAmount;
        vars.totalSupplyNew = totalSupply - vars.protocolSeizeTokens;

        vars.liquidatorTokensNew = accountTokens[liquidator] + vars.liquidatorSeizeTokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        totalReserves = vars.totalReservesNew;
        totalSupply = vars.totalSupplyNew;
        accountTokens[borrower] = vars.borrowerTokensNew;
        accountTokens[liquidator] = vars.liquidatorTokensNew;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, vars.liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), vars.protocolSeizeTokens);
        emit ReservesAdded(address(this), vars.protocolSeizeAmount, vars.totalReservesNew);

        /* We call the defense hook */
        // unused function
        // comptroller.seizeVerify(address(this), seizerToken, liquidator, borrower, seizeTokens);
    }


    /*** Admin Functions ***/

    /**
      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      */
    function _setPendingAdmin(address payable newPendingAdmin) external override  {
        // Check caller = admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      * @dev Admin function for pending admin to accept role and update admin
      */
    function _acceptAdmin() external override{
        // Check caller is pendingAdmin
        if (msg.sender != pendingAdmin) {
            revert Unauthorized();
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = payable(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
      * @notice Sets a new comptroller for the market
      * @dev Admin function to set a new comptroller
      */
    function _setComptroller(ComptrollerInterface newComptroller) public override{
        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        ComptrollerInterface oldComptroller = comptroller;
        // Ensure invoke comptroller.isComptroller() returns true
        require(newComptroller.isComptroller(), "marker method returned false");

        // Set market's comptroller to newComptroller
        comptroller = newComptroller;

        // Emit NewComptroller(oldComptroller, newComptroller)
        emit NewComptroller(oldComptroller, newComptroller);
    }

    /**
      * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
      * @dev Admin function to accrue interest and set a new reserve factor
      */
    function _setReserveFactor(uint newReserveFactorMantissa) external override nonReentrant{
        accrueInterest();
        _setReserveFactorFresh(newReserveFactorMantissa);
    }

    /**
      * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
      * @dev Admin function to set a new reserve factor
      */
    function _setReserveFactorFresh(uint newReserveFactorMantissa) internal{
        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // Verify market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorMantissa > reserveFactorMaxMantissa) {
            revert BadInput();
        }

        uint oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring from msg.sender
     * @param addAmount Amount of addition to reserves
     */
    function _addReservesInternal(uint addAmount) internal nonReentrant{
        accrueInterest();
        _addReservesFresh(addAmount);
    }

    /**
     * @notice Add reserves by transferring from caller
     * @dev Requires fresh interest accrual
     * @param addAmount Amount of addition to reserves
     * @return (uint, uint) An error code (0=success, otherwise a failure (see ErrorReporter.sol for details)) and the actual amount added, net token fees
     */
    function _addReservesFresh(uint addAmount) internal returns (uint) {
        // totalReserves + actualAddAmount
        uint totalReservesNew;
        uint actualAddAmount;

        // We revert unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  Note: The auToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the auToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = totalReserves + actualAddAmount;

        /* Revert on overflow */
        require(totalReservesNew >= totalReserves, "add reserves unexpected overflow");

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);

        return actualAddAmount;
    }


    /**
     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param reduceAmount Amount of reduction to reserves
     */
    function _reduceReserves(uint reduceAmount) external override nonReentrant{
        accrueInterest();
        _reduceReservesFresh(reduceAmount);
    }

    /**
     * @notice Reduces reserves by transferring to admin
     * @dev Requires fresh interest accrual
     * @param reduceAmount Amount of reduction to reserves
     */
    function _reduceReservesFresh(uint reduceAmount) internal{
        // totalReserves - reduceAmount
        uint totalReservesNew;

        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // We revert unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        // Revert if protocol has insufficient underlying cash
        if (getCashPrior() < reduceAmount) {
            revert TokenInsufficientCash();
        }

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        if (reduceAmount > totalReserves) {
            revert BadInput();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        totalReservesNew = totalReserves - reduceAmount;
        // We checked reduceAmount <= totalReserves above, so this should never revert.
        require(totalReservesNew <= totalReserves, "reduce reserves unexpected underflow");

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, reduceAmount, totalReservesNew);
    }

    /**
     * @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public override {
        accrueInterest();
        _setInterestRateModelFresh(newInterestRateModel);
    }

    /**
     * @notice updates the interest rate model (*requires fresh interest accrual)
     * @dev Admin function to update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function _setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal {

        // Used to store old model for use in the event that is emitted on success
        InterestRateModel oldInterestRateModel;

        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // We revert unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        // Track the market's current interest rate model
        oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        require(newInterestRateModel.isInterestRateModel(), "marker method returned false");

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel);
    }

    /**
     * @notice accrues interest and updates the protocol seize share using _setProtocolSeizeShareFresh
     * @dev Admin function to accrue interest and update the protocol seize share
     * @param newProtocolSeizeShareMantissa the new protocol seize share to use
     */
    function _setProtocolSeizeShare(uint newProtocolSeizeShareMantissa) external override nonReentrant{
        accrueInterest();
        _setProtocolSeizeShareFresh(newProtocolSeizeShareMantissa);
    }

    /**
     * @notice updates the protocol seize share (*requires fresh interest accrual)
     * @dev Admin function to update the protocol seize share
     * @param newProtocolSeizeShareMantissa the new protocol seize share to use
     */
    function _setProtocolSeizeShareFresh(uint newProtocolSeizeShareMantissa) internal{

        // Used to store old share for use in the event that is emitted on success
        uint oldProtocolSeizeShareMantissa;

        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }
        // We revert unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert MarketNotFresh();
        }

        // Track the market's current protocol seize share
        oldProtocolSeizeShareMantissa = protocolSeizeShareMantissa;

        // Set the protocol seize share to newProtocolSeizeShareMantissa
        protocolSeizeShareMantissa = newProtocolSeizeShareMantissa;

        // Emit NewProtocolSeizeShareMantissa(oldProtocolSeizeShareMantissa, newProtocolSeizeShareMantissa)
        emit NewProtocolSeizeShare(oldProtocolSeizeShareMantissa, newProtocolSeizeShareMantissa);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying owned by this contract
     */
    function getCashPrior() internal view virtual returns (uint);

    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     */
    function doTransferIn(address from, uint amount) internal virtual returns (uint);

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure tather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     */
    function doTransferOut(address payable to, uint amount) internal virtual;
}
