pragma solidity 0.8.11;

import "./AuToken.sol";
import "./interfaces/PriceOracle.sol";
import "./interfaces/ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";

/**
 * @title Aurigami Finance's Comptroller Contract
 */
contract Comptroller is ComptrollerVXStorage, ComptrollerInterface, ExponentialNoError {
    error Unauthorized();
    error MarketNotListed();
    error InsufficientLiquidity();
    error PriceError();
    error NonzeroBorrowBalance();
    error InsufficientShortfall();
    error TooMuchRepay();
    error InvalidCollateralFactor();
    error MarketAlreadyListed();
    error MarketCollateralFactorZero();

    /// @notice Emitted when an admin supports a market
    event MarketListed(AuToken auToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(AuToken auToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(AuToken auToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(AuToken auToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(AuToken auToken, string action, bool pauseState);

    /// @notice Emitted when a new PLY or AURORA speed is calculated for a market
    event SpeedUpdated(uint8 tokenType, AuToken indexed auToken, bool isSupply, uint newSpeed);

    /// @notice Emitted when a new PLY speed is set for a contributor
    event ContributorPlySpeedUpdated(address indexed contributor, uint newSpeed);

    /// @notice Emitted when PLY or AURORA is distributed to a borrower
    event DistributedBorrowerReward(uint8 indexed tokenType, AuToken indexed auToken, address indexed borrower, uint plyDelta, uint plyBorrowIndex);

    /// @notice Emitted when PLY or AURORA is distributed to a supplier
    event DistributedSupplierReward(uint8 indexed tokenType, AuToken indexed auToken, address indexed borrower, uint plyDelta, uint plyBorrowIndex);

    /// @notice Emitted when borrow cap for a auToken is changed
    event NewBorrowCap(AuToken indexed auToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when PLY is granted by admin
    event PlyGranted(address recipient, uint amount);

    /// @notice Emitted when the whitelist status of an address is changed
    event WhitelistStatusChanged(address addr, bool newStatus);

    /// @notice The initial PLY and AURORA index for a market
    uint224 public constant initialIndexConstant = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    // reward token type to show PLY or AURORA
    uint8 public constant rewardPly = 0;
    uint8 public constant rewardAurora = 1;

    constructor() {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     */
    function getAssetsIn(address account) external view returns (AuToken[] memory assetsIn) {
        assetsIn = accountAssets[account];
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param auToken The auToken to check
     */
    function checkMembership(address account, AuToken auToken) external view returns (bool) {
        return markets[address(auToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param auTokens The list of addresses of the auToken markets to be enabled
     */
    function enterMarkets(address[] memory auTokens) public override{
        uint len = auTokens.length;
        for (uint i = 0; i < len; i++) {
            AuToken auToken = AuToken(auTokens[i]);
            addToMarketInternal(auToken, msg.sender);
        }
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param auToken The market to enter
     * @param borrower The address of the account to modify
     */
    function addToMarketInternal(AuToken auToken, address borrower) internal {
        Market storage marketToJoin = markets[address(auToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            revert MarketNotListed();
        }

        if (marketToJoin.collateralFactorMantissa == 0){
            // market has collateral factor == 0, joining this market is meaningless
            // hence, it's better for users not to join to conserve gas cost
            revert MarketCollateralFactorZero();
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(auToken);

        require(accountAssets[borrower].length <= maxAssets, "max assets reached");

        emit MarketEntered(auToken, borrower);
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param auTokenAddress The address of the asset to be removed
     */
    function exitMarket(address auTokenAddress) external override {
        AuToken auToken = AuToken(auTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the auToken */
        (uint tokensHeld, uint amountOwed, ) = auToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            revert NonzeroBorrowBalance();
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        redeemAllowedInternal(auTokenAddress, msg.sender, tokensHeld);

        Market storage marketToExit = markets[address(auToken)];

        /* Return if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return;
        }

        /* Set auToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete auToken from the account’s list of assets */
        // load into memory for faster iteration
        AuToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == auToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, and then pop it
        AuToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(auToken, msg.sender);

        return;
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param auToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     */
    function mintAllowed(address auToken, address minter, uint mintAmount) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[auToken], "mint is paused");

        // Shh - currently unused
        mintAmount;

        if (!markets[auToken].isListed) {
            revert MarketNotListed();
        }

        updateAndDistributeSupplierRewardsForTokenForOne(auToken, minter);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param auToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of auTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(address auToken, address redeemer, uint redeemTokens) external override {
        redeemAllowedInternal(auToken, redeemer, redeemTokens);

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForTokenForOne(auToken, redeemer);
    }

    function redeemAllowedInternal(address auToken, address redeemer, uint redeemTokens) internal view {
        if (!markets[auToken].isListed) {
            revert MarketNotListed();
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[auToken].accountMembership[redeemer]) {
            return;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, AuToken(auToken), redeemTokens, 0);
        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param auToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(address auToken, address borrower, uint borrowAmount) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[auToken], "borrow is paused");

        if (!markets[auToken].isListed) {
            revert MarketNotListed();
        }

        if (!markets[auToken].accountMembership[borrower]) {
            // only auTokens may call borrowAllowed if borrower not in market
            require(msg.sender == auToken, "sender must be auToken");

            // attempt to add borrower to the market
            addToMarketInternal(AuToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(markets[auToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(AuToken(auToken)) == 0) {
            revert PriceError();
        }

        uint borrowCap = borrowCaps[auToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = AuToken(auToken).totalBorrows();
            uint nextTotalBorrows = totalBorrows + borrowAmount;
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, AuToken(auToken), 0, borrowAmount);
        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }

        // Keep the flywheel moving
        Exp borrowIndex = Exp.wrap(AuToken(auToken).borrowIndex());
        updateAndDistributeBorrowerRewardsForToken(auToken, borrower, borrowIndex);
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param auToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     */
    function repayBorrowAllowed(
        address auToken,
        address payer,
        address borrower,
        uint repayAmount) external override {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[auToken].isListed) {
            revert MarketNotListed();
        }

        // Keep the flywheel moving
        Exp borrowIndex = Exp.wrap(AuToken(auToken).borrowIndex());
        updateAndDistributeBorrowerRewardsForToken(auToken, borrower, borrowIndex);
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param auTokenBorrowed Asset which was borrowed by the borrower
     * @param auTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address auTokenBorrowed,
        address auTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external view override {
        // Shh - currently unused
        liquidator;

        if (!markets[auTokenBorrowed].isListed || !markets[auTokenCollateral].isListed) {
            revert MarketNotListed();
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (, uint shortfall) = getAccountLiquidityInternal(borrower);
        if (shortfall == 0) {
            revert InsufficientShortfall();
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = AuToken(auTokenBorrowed).borrowBalanceStored(borrower);
        uint maxClose = mul_ScalarTruncate(Exp.wrap(closeFactorMantissa), borrowBalance);
        if (repayAmount > maxClose) {
            revert TooMuchRepay();
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param auTokenCollateral Asset which was used as collateral and will be seized
     * @param auTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address auTokenCollateral,
        address auTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[auTokenCollateral].isListed || !markets[auTokenBorrowed].isListed) {
            revert MarketNotListed();
        }

        // it will be guaranteed by Governance that comptroller of 2 auTokens are the same
        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForTokenForTwo(auTokenCollateral, borrower, liquidator);
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param auToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of auTokens to transfer
     */
    function transferAllowed(address auToken, address src, address dst, uint transferTokens) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        redeemAllowedInternal(auToken, src, transferTokens);

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForTokenForTwo(auToken, src, dst);
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `auTokenBalance` is the number of auTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint auTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, AuToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return account liquidity in excess of collateral requirements,
               account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, AuToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param auTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return hypothetical account liquidity in excess of collateral requirements,
               hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address auTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint) {
        return  getHypotheticalAccountLiquidityInternal(account, AuToken(auTokenModify), redeemTokens, borrowAmount);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param auTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral auToken using stored data,
     *  without calculating accumulated interest.
     * @return hypothetical account liquidity in excess of collateral requirements,
               hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        AuToken auTokenModify,
        uint redeemTokens,
        uint borrowAmount) internal view returns (uint, uint) {

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        // For each asset the account is in
        AuToken[] memory assets = accountAssets[account];
        uint256[] memory priceOfAssets = oracle.getUnderlyingPrices(assets);

        for (uint i = 0; i < assets.length; i++) {
            AuToken asset = assets[i];

            // Read the balances and exchange rate from the auToken
            (vars.auTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);

            vars.collateralFactor = Exp.wrap(markets[address(asset)].collateralFactorMantissa);
            vars.exchangeRate = Exp.wrap(vars.exchangeRateMantissa);

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = priceOfAssets[i];
            if (vars.oraclePriceMantissa == 0) {
                revert PriceError();
            }

            vars.oraclePrice = Exp.wrap(vars.oraclePriceMantissa);

            // Pre-compute a conversion factor from tokens -> usd (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * auTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.auTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with auTokenModify
            if (asset == auTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in auToken.liquidateBorrowFresh)
     * @param auTokenBorrowed The address of the borrowed auToken
     * @param auTokenCollateral The address of the collateral auToken
     * @param actualRepayAmount The amount of auTokenBorrowed underlying to convert into auTokenCollateral tokens
     */
    function liquidateCalculateSeizeTokens(address auTokenBorrowed, address auTokenCollateral, uint actualRepayAmount) external view override returns (uint) {
        /* Read oracle prices for borrowed and collateral markets */
        AuToken[] memory queries = new AuToken[](2);
        queries[0] = AuToken(auTokenBorrowed);
        queries[1] = AuToken(auTokenCollateral);
        uint256[] memory prices = oracle.getUnderlyingPrices(queries);

        uint priceBorrowedMantissa = prices[0];
        uint priceCollateralMantissa = prices[1];
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            revert PriceError();
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = AuToken(auTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp numerator;
        Exp denominator;
        Exp ratio;


        // moved actualRepayAmount here to account for decimal difference issue
        numerator = mul_(mul_(Exp.wrap(liquidationIncentiveMantissa), Exp.wrap(priceBorrowedMantissa)), actualRepayAmount);
        denominator = mul_(Exp.wrap(priceCollateralMantissa), Exp.wrap(exchangeRateMantissa));
        ratio = div_(numerator, denominator);

        // multiplication done in numerator, only truncation here
        seizeTokens = truncate(ratio);

        return seizeTokens;
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the comptroller
      * @dev Admin function to set a new price oracle
      */
    function _setPriceOracle(PriceOracle newOracle) public {
        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      */
    function _setCloseFactor(uint newCloseFactorMantissa) external {
        // Check caller is admin
    	require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param auToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      */
    function _setCollateralFactor(AuToken auToken, uint newCollateralFactorMantissa) external {
        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }
        // Verify market is listed
        Market storage market = markets[address(auToken)];
        if (!market.isListed) {
            revert MarketNotListed();
        }

        Exp newCollateralFactorExp = Exp.wrap(newCollateralFactorMantissa);

        // Check collateral factor <= 0.9
        Exp highLimit = Exp.wrap(collateralFactorMaxMantissa);
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            revert InvalidCollateralFactor();
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(auToken) == 0) {
            revert PriceError();
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(auToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external {
        // Check caller is admin
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param auToken The address of the market (token) to list
      */
    function _supportMarket(AuToken auToken) external {
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        if (markets[address(auToken)].isListed) {
            revert MarketAlreadyListed();
        }

        auToken.isAuToken(); // Sanity check to make sure its really a AuToken

        // Note that isPlyed is not in active use anymore
        markets[address(auToken)].isListed = true;

        _addMarketInternal(address(auToken));

        emit MarketListed(auToken);
    }

    function _addMarketInternal(address auToken) internal {
        for (uint i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != AuToken(auToken), "market already added");
        }
        allMarkets.push(AuToken(auToken));
    }

    /**
      * @notice Set the given borrow caps for the given auToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param auTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function _setMarketBorrowCaps(AuToken[] calldata auTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian");

        uint numMarkets = auTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(auTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(auTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function _setPauseGuardian(address newPauseGuardian) public {
        if (msg.sender != admin) {
            revert Unauthorized();
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    function _setMintPaused(AuToken auToken, bool state) public returns (bool) {
        require(markets[address(auToken)].isListed, "cannot pause a market that is not listed");
        checkPauserPermission(state);

        mintGuardianPaused[address(auToken)] = state;
        emit ActionPaused(auToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(AuToken auToken, bool state) public returns (bool) {
        require(markets[address(auToken)].isListed, "cannot pause a market that is not listed");
        checkPauserPermission(state);

        borrowGuardianPaused[address(auToken)] = state;
        emit ActionPaused(auToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        checkPauserPermission(state);

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        checkPauserPermission(state);

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        unitroller._acceptImplementation();
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view {
        require(msg.sender == admin || msg.sender == comptrollerImplementation, "unauthorized");
    }

    function checkPauserPermission(bool state) internal view {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state, "only admin can unpause");
    }

    /*** PLY Distribution ***/

    /**
     * @notice Set PLY/AURORA speed for a single market
     * @param rewardType  0: Ply, 1: Aurora
     * @param auToken The market whose PLY speed to update
     * @param newSpeed New PLY or AURORA speed for market
     * @param isSupply true = set lending speed, false = set borrow speed
     */
    function setRewardSpeedInternal(uint8 rewardType, AuToken auToken, uint newSpeed, bool isSupply) internal {
        uint currentRewardSpeed = rewardSpeeds[rewardType][address(auToken)][isSupply];
        if (isSupply) {
            updateRewardSupplyIndex(rewardType, address(auToken), auToken.totalSupply());
        } else {
            // note that PLY speed could be set to 0 to halt liquidity rewards for a market
            Exp borrowIndex = Exp.wrap(auToken.borrowIndex());
            updateRewardBorrowIndex(rewardType, address(auToken), borrowIndex, auToken.totalBorrows());
        }

        if (currentRewardSpeed == 0 && newSpeed != 0) {
            // Add the PLY market
            Market storage market = markets[address(auToken)];
            require(market.isListed, "PLY market is not listed");

            if (isSupply && rewardSupplyState[rewardType][address(auToken)].index == 0) {
                rewardSupplyState[rewardType][address(auToken)] = RewardMarketState({
                    index: initialIndexConstant,
                    timestamp: uint32(block.timestamp)
                });
            }

            if (!isSupply && rewardBorrowState[rewardType][address(auToken)].index == 0) {
                rewardBorrowState[rewardType][address(auToken)] = RewardMarketState({
                    index: initialIndexConstant,
                    timestamp: uint32(block.timestamp)
                });
            }
        }

        if (currentRewardSpeed != newSpeed) {
            rewardSpeeds[rewardType][address(auToken)][isSupply] = newSpeed;
            emit SpeedUpdated(rewardType, auToken, isSupply, newSpeed);
        }
    }

    /**
     * @notice Accrue PLY to the market by updating the supply index
     * @param rewardType  0: Ply, 1: Aurora
     * @param auToken The market whose supply index to update
     */
    function updateRewardSupplyIndex(uint8 rewardType, address auToken, uint256 totalSupplyOfAuToken) internal virtual{
        checkRewardType(rewardType);
        RewardMarketState storage supplyState = rewardSupplyState[rewardType][auToken];
        uint supplySpeed = rewardSpeeds[rewardType][auToken][true];
        uint deltaTimestamps = block.timestamp - uint(supplyState.timestamp);
        if (deltaTimestamps > 0 && supplySpeed > 0) {
            uint rewardAccrued = deltaTimestamps * supplySpeed;
            Double ratio = totalSupplyOfAuToken > 0 ? fraction(rewardAccrued, totalSupplyOfAuToken) : Double.wrap(0);
            Double index = add_(Double.wrap(supplyState.index), ratio);
            rewardSupplyState[rewardType][auToken] = RewardMarketState({
                index: safe224(Double.unwrap(index)),
                timestamp: uint32(block.timestamp)
            });
        } else if (deltaTimestamps > 0) {
            supplyState.timestamp = uint32(block.timestamp);
        }
    }

    /**
     * @notice Accrue PLY to the market by updating the borrow index
     * @param rewardType  0: Ply, 1: Aurora
     * @param auToken The market whose borrow index to update
     */
    function updateRewardBorrowIndex(uint8 rewardType, address auToken, Exp marketBorrowIndex, uint256 totalBorrowsOfAuToken) internal virtual{
        checkRewardType(rewardType);
        RewardMarketState storage borrowState = rewardBorrowState[rewardType][auToken];
        uint borrowSpeed = rewardSpeeds[rewardType][auToken][false];
        uint deltaTimestamps = block.timestamp - uint(borrowState.timestamp);
        if (deltaTimestamps > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(totalBorrowsOfAuToken, marketBorrowIndex);
            uint rewardAccrued = deltaTimestamps * borrowSpeed;
            Double ratio = borrowAmount > 0 ? fraction(rewardAccrued, borrowAmount) : Double.wrap(0);
            Double index = add_(Double.wrap(borrowState.index), ratio);
            rewardBorrowState[rewardType][auToken] = RewardMarketState({
                index: safe224(Double.unwrap(index)),
                timestamp: uint32(block.timestamp)
            });
        } else if (deltaTimestamps > 0) {
            borrowState.timestamp = uint32(block.timestamp);
        }
    }

    /**
     * @notice Refactored function to calc and rewards accounts supplier rewards
     * @param auToken The market to verify the mint against
     * @param supplier The acount to whom PLY or AURORA is rewarded
     */
    function updateAndDistributeSupplierRewardsForTokenForOne(address auToken, address supplier) internal virtual{
        (uint256 totalSupplyOfAuToken, uint256 auTokenBalance) = AuToken(auToken).getSupplyDataOfOneAccount(supplier);
        for (uint8 rewardType = 0; rewardType <= 1; rewardType++) {
            updateRewardSupplyIndex(rewardType, auToken, totalSupplyOfAuToken);
            distributeSupplierReward(rewardType, auToken, supplier, auTokenBalance);
        }
    }

    function updateAndDistributeSupplierRewardsForTokenForTwo(address auToken, address supplier1, address supplier2) internal virtual{
        (uint256 totalSupplyOfAuToken, uint256 auTokenBalance1, uint256 auTokenBalance2) = AuToken(auToken).getSupplyDataOfTwoAccount(supplier1, supplier2);
        for (uint8 rewardType = 0; rewardType <= 1; rewardType++) {
            updateRewardSupplyIndex(rewardType, auToken, totalSupplyOfAuToken);
            distributeSupplierReward(rewardType, auToken, supplier1, auTokenBalance1);
            distributeSupplierReward(rewardType, auToken, supplier2, auTokenBalance2);
        }
    }

    /**
     * @notice Calculate PLY/AURORA accrued by a supplier and possibly transfer it to them
     * @param rewardType  0: Ply, 1: Aurora
     * @param auToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute PLY to
     */
    function distributeSupplierReward(uint8 rewardType, address auToken, address supplier, uint256 supplierBalanceOfAuToken) internal virtual {
        checkRewardType(rewardType);
        RewardMarketState storage supplyState = rewardSupplyState[rewardType][auToken];
        Double supplyIndex = Double.wrap(supplyState.index);
        Double supplierIndex = Double.wrap(rewardSupplierIndex[rewardType][auToken][supplier]);
        rewardSupplierIndex[rewardType][auToken][supplier] = Double.unwrap(supplyIndex);

        if (Double.unwrap(supplierIndex) == 0 && Double.unwrap(supplyIndex) > 0) {
            supplierIndex = Double.wrap(initialIndexConstant);
        }


        Double deltaIndex = sub_(supplyIndex, supplierIndex);

        uint supplierDelta = mul_(supplierBalanceOfAuToken, deltaIndex);
        uint supplierAccrued = rewardAccrued[rewardType][supplier] + supplierDelta;
        rewardAccrued[rewardType][supplier] = supplierAccrued;
        emit DistributedSupplierReward(rewardType, AuToken(auToken), supplier, supplierDelta, Double.unwrap(supplyIndex));
    }

   /**
     * @notice Refactored function to calc and rewards accounts supplier rewards
     * @param auToken The market to verify the mint against
     * @param borrower Borrower to be rewarded
     */
    function updateAndDistributeBorrowerRewardsForToken(address auToken, address borrower, Exp marketBorrowIndex) internal virtual {
        (uint256 totalBorrowsOfAuToken, uint256 borrowBalanceStoredOfBorrower) = AuToken(auToken).getBorrowDataOfAccount(borrower);
        for (uint8 rewardType = 0; rewardType <= 1; rewardType++) {
            updateRewardBorrowIndex(rewardType, auToken, marketBorrowIndex, totalBorrowsOfAuToken);
            distributeBorrowerReward(rewardType, auToken, borrower, marketBorrowIndex, borrowBalanceStoredOfBorrower);
        }
    }

    /**
     * @notice Calculate PLY accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param rewardType  0: Ply, 1: Aurora
     * @param auToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute PLY to
     */
    function distributeBorrowerReward(uint8 rewardType, address auToken, address borrower, Exp marketBorrowIndex, uint256 borrowBalanceStoredOfBorrower) internal virtual{
        checkRewardType(rewardType);
        RewardMarketState storage borrowState = rewardBorrowState [rewardType][auToken];
        Double borrowIndex = Double.wrap(borrowState.index);
        Double borrowerIndex = Double.wrap(rewardBorrowerIndex[rewardType][auToken][borrower]);
        rewardBorrowerIndex[rewardType][auToken][borrower] = Double.unwrap(borrowIndex);

        if (Double.unwrap(borrowerIndex) == 0 && Double.unwrap(borrowIndex) > 0) {
            borrowerIndex = Double.wrap(initialIndexConstant);
        }

        Double deltaIndex = sub_(borrowIndex, borrowerIndex);
        uint borrowerAmount = div_(borrowBalanceStoredOfBorrower, marketBorrowIndex);
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
        uint borrowerAccrued = rewardAccrued[rewardType][borrower] + borrowerDelta;
        rewardAccrued[rewardType][borrower] = borrowerAccrued;
        emit DistributedBorrowerReward(rewardType, AuToken(auToken), borrower, borrowerDelta, Double.unwrap(borrowIndex));
    }

    /**
     * @notice Claim all the PLY accrued by holder in all markets
     * @param holder The address to claim PLY for
     */
    function claimReward(uint8 rewardType, address holder) external {
        _claimRewardForOne(rewardType, holder, allMarkets, true, true);
    }

    /**
     * @notice Claim all the PLY accrued by holder in the specified markets
     * @param holder The address to claim PLY for
     * @param auTokens The list of markets to claim PLY in
     */
    function claimReward(uint8 rewardType, address holder, AuToken[] memory auTokens) external {
        _claimRewardForOne(rewardType, holder, auTokens, true, true);
    }

    /**
     * @notice Claim all PLY or AURORA accrued by the holders
     * @param rewardType  0: Ply, 1: Aurora
     * @param holders The addresses to claim PLY / AURORA for
     * @param auTokens The list of markets to claim PLY / AURORA in
     * @param borrowers Whether or not to claim PLY / AURORA earned by borrowing
     * @param suppliers Whether or not to claim PLY / AURORA earned by supplying
     */
    function claimReward(uint8 rewardType, address[] memory holders, AuToken[] memory auTokens, bool borrowers, bool suppliers) external {
        for(uint256 i = 0; i < holders.length; i++) {
            _claimRewardForOne(rewardType, holders[i], auTokens, borrowers, suppliers);
        }
    }

    /**
     * @notice Claim all PLY or AURORA accrued by one holder
     * @notice Only whitelisted address can claim the rewards for other users. This is to prevent users to lock others' reward into token lock.
     * @param rewardType  0: Ply, 1: Aurora
     * @param holder The address to claim PLY / AURORA for
     * @param auTokens The list of markets to claim PLY / AURORA in
     * @param borrowers Whether or not to claim PLY / AURORA earned by borrowing
     * @param suppliers Whether or not to claim PLY / AURORA earned by supplying
     */
    function _claimRewardForOne(uint8 rewardType, address holder, AuToken[] memory auTokens, bool borrowers, bool suppliers) internal {
        checkRewardType(rewardType);
        require(borrowers||suppliers,"either borrow or supply must be true");
        require(isAllowedToClaimReward(holder, msg.sender), "not approved");

        for (uint i = 0; i < auTokens.length; i++) {
            AuToken auToken = auTokens[i];
            require(markets[address(auToken)].isListed, "market must be listed");
            if (borrowers) {
                Exp borrowIndex = Exp.wrap(auToken.borrowIndex());
                (uint totalBorrows, uint borrowBalanceStored) = auToken.getBorrowDataOfAccount(holder);
                updateRewardBorrowIndex(rewardType, address(auToken), borrowIndex, totalBorrows);
                distributeBorrowerReward(rewardType, address(auToken), holder, borrowIndex, borrowBalanceStored);
            }
            if (suppliers) {
                (uint totalSupply, uint auTokenBalance) = auToken.getSupplyDataOfOneAccount(holder);
                updateRewardSupplyIndex(rewardType, address(auToken), totalSupply);
                distributeSupplierReward(rewardType, address(auToken), holder, auTokenBalance);
            }
        }

        uint256 holderReward = rewardAccrued[rewardType][holder];
        rewardAccrued[rewardType][holder] = 0;

        doTransferOutRewards(rewardType, holder, holderReward);
    }


    /**
     * @notice Transfer PLY/AURORA to the user
     * @dev Note: If there is not enough PLY/AURORA, we will revert
     * @param user The address of the user to transfer PLY/AURORA to
     */
    function doTransferOutRewards(uint rewardType, address user, uint amount) internal {
        if (amount == 0) return;

        if (rewardType == 0) {
            // calculate lock and claim amounts
            (uint256 lockAmount, uint256 claimAmount) = pulp.calcLockAmount(user, amount);
            if (lockAmount > 0) {
                ply.approve(address(pulp), lockAmount);
                pulp.lockPly(user, lockAmount);
            }
            if (claimAmount > 0) ply.transfer(user, claimAmount);
        } else if (rewardType == 1) {
            aurora.transfer(user, amount);
        }
    }

    /*** PLY Distribution Admin ***/

    /**
     * @notice Transfer PLY to the recipient
     * @dev Note: If there is not enough PLY, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer PLY to
     * @param amount The amount of PLY to (possibly) transfer
     */
    function _grantPly(address recipient, uint amount) public {
        adminOrInitializing();
        doTransferOutRewards(0, recipient, amount);
        emit PlyGranted(recipient, amount);
    }

    /**
     * @notice Set reward speeds for a multiple markets
     * @param rewardType 0 = PLY, 1 = AURORA
     * @param auTokens The markets whose reward speed to update
     * @param rewardSpeeds New reward speeds for market
     * @param isSupply true = set lending speed, false = set borrow speed
     */
    function _setRewardSpeeds(uint8 rewardType, AuToken[] calldata auTokens, uint[] calldata rewardSpeeds, bool[] calldata isSupply) external {
        checkRewardType(rewardType);
        adminOrInitializing();
        require(auTokens.length == rewardSpeeds.length, "Invalid array length");
        require(auTokens.length == isSupply.length, "Invalid array length");
        for (uint i = 0; i < auTokens.length; i++) {
            setRewardSpeedInternal(rewardType, auTokens[i], rewardSpeeds[i], isSupply[i]);
        }
    }

    /**
     * @notice Set the maximum number of markets users can be in
     * @dev the limit of maxAssets will only be applied when users join new markets, so if this limit is
     reduced, users that are already in more markets than allowed will still be able to use the protocol
     normally (except the user cannot enter new markets)
     */
    function _setMaxAssets(uint256 _maxAssets) external {
        adminOrInitializing();
        require(_maxAssets != 0,"zero input");
        maxAssets = _maxAssets;
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     */
    function getAllMarkets() public view returns (AuToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Set the PLY and aurora token addresses
     */
    function setTokens(EIP20Interface newPly, EIP20Interface newAurora) external {
        adminOrInitializing();
        ply = newPly;
        aurora = newAurora;
    }

    /**
     * @notice Set the token lock address
     */
    function setLockAddress(PULPInterface newPulp) external {
        adminOrInitializing();
        pulp = newPulp;
    }

    /**
     * @notice Set the reward claim timestamp
     */
    function setRewardClaimStart(uint32 newRewardClaimStart) external {
        adminOrInitializing();
        require((rewardClaimStart > block.timestamp || rewardClaimStart == 0) && newRewardClaimStart > block.timestamp, "invalid timestamp");
        rewardClaimStart = newRewardClaimStart;
    }

    function checkRewardType(uint8 rewardType) internal pure {
        require(rewardType <= 1, "rewardType is invalid");
    }

    /**
     * @notice Include / exclude an address from the whitelist. Only callable by admin
     */
    function setWhitelisted(address addr, bool whitelisted) external {
        adminOrInitializing();
        isWhitelisted[addr] = whitelisted;
        emit WhitelistStatusChanged(addr, whitelisted);
    }

    function isAllowedToClaimReward(address user, address claimer) public view returns (bool){
        return (user==claimer || isWhitelisted[claimer]);
    }
}
