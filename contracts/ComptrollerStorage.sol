pragma solidity 0.8.11;

import "./AuToken.sol";
import "./interfaces/PriceOracle.sol";
import "./interfaces/RewardsClaimInterface.sol";
import "./interfaces/PULPInterface.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public comptrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingComptrollerImplementation;
}

contract ComptrollerVXStorage is UnitrollerAdminStorage, RewardsClaimInterface {

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => AuToken[]) public accountAssets;

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;

        /// @notice Whether or not this market receives PLY
        bool isPlyed;
    }

    /**
     * @notice Official mapping of AuTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;


    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    /// @notice A list of all markets
    AuToken[] public allMarkets;

    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each AuToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;

    struct RewardMarketState {
        /// @notice The market's last updated rewardBorrowIndex or rewardSupplyIndex
        uint224 index;

        /// @notice The block timestamp the index was last updated at
        uint32 timestamp;
    }

    /// @notice The rate at which the flywheel distributes reward, per timestamp
    mapping(uint8 => uint) public rewardRate;

    /// @notice The portion of reward rate that each market currently receives
    mapping(uint8 => mapping(address => mapping(bool => uint))) public rewardSpeeds;

    /// @notice The PLY/AURORA market supply state for each market
    mapping(uint8 => mapping(address => RewardMarketState)) public rewardSupplyState;

    /// @notice The PLY/AURORA market borrow state for each market
    mapping(uint8 =>mapping(address => RewardMarketState)) public rewardBorrowState;

    /// @notice The PLY/AURORA borrow index for each market for each supplier as of the last time they accrued reward
    mapping(uint8 => mapping(address => mapping(address => uint))) public rewardSupplierIndex;

    /// @notice The PLY/AURORA borrow index for each market for each borrower as of the last time they accrued reward
    mapping(uint8 => mapping(address => mapping(address => uint))) public rewardBorrowerIndex;

    /// @notice The PLY/AURORA accrued but not yet transferred to each user
    mapping(uint8 => mapping(address => uint)) public rewardAccrued;

    /// @notice User => Approved for reward claiming
    mapping(address => bool) public isWhitelisted;

    /// @notice PLY token contract address
    EIP20Interface public ply;

    /// @notice AURORA token contract address
    EIP20Interface public aurora;

    /// @notice token lock address
    PULPInterface public pulp;

    /// @notice start timestamp for liquidity incentive claims
    uint32 public rewardClaimStart;
}
