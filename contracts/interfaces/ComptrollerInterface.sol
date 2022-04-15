pragma solidity 0.8.11;

abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata plyTokens) external virtual;
    function exitMarket(address plyToken) external virtual;

    /*** Policy Hooks ***/

    function mintAllowed(address plyToken, address minter, uint mintAmount) external virtual;

    function redeemAllowed(address plyToken, address redeemer, uint redeemTokens) external virtual;

    function borrowAllowed(address plyToken, address borrower, uint borrowAmount) external virtual;

    function repayBorrowAllowed(
        address plyToken,
        address payer,
        address borrower,
        uint repayAmount) external virtual;

    function liquidateBorrowAllowed(
        address plyTokenBorrowed,
        address plyTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external virtual;

    function seizeAllowed(
        address plyTokenCollateral,
        address plyTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external virtual;

    function transferAllowed(address plyToken, address src, address dst, uint transferTokens) external virtual;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address plyTokenBorrowed,
        address plyTokenCollateral,
        uint repayAmount) external view virtual returns (uint);
}
