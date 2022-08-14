pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./RNG.sol";
import "./PlyGameSettings.sol";

contract PlyGame is PlyGameSettings, RNG, UUPSUpgradeable {
  enum Outcome {
    BigWin,
    Win,
    Lose,
    NoImpact
  }

  struct Game {
    address player;
    Outcome outcome;
    uint128 amount;
    uint128 cumulativeAmount;
  }

  struct JackpotHistory {
    address winner;
    uint256 amount;
  }

  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeCast for uint256;
  using SafeCast for uint128;
  using SafeCast for uint64;

  mapping(address => uint256[]) public pastBlocks;
  mapping(address => uint256) public totalPlyUnlockedEarly;

  uint256 public currentJackpotAmount;

  Game[] public games;
  JackpotHistory[] public jackpotHistory;
  uint256 public firstJackpotTicket;

  bool public gameOpened;
  uint256 public lastUnlockFetch;

  /// @notice emitted when a game changes open state
  event GameOpened(bool openState);

  /// @notice emitted when a bet is made
  event BetMade(address indexed player, uint256 amount, Outcome indexed outcome);

  /// @notice emitted when a jackpot winner is declared
  event JackpotWinner(address indexed winner, uint256 amount);

  constructor(address _ply) initializer PlyGameSettings(_ply) {}

  function initialize(
    address house_,
    uint256 minAmount_,
    uint256 maxAmount_,
    uint256 bigWinProb_,
    uint256 winProb_,
    uint256 loseProb_,
    uint256 noImpactProb_
  ) external initializer {
    __BoringOwnable_init();
    require(house_ != address(0), "invalid house address");
    require(minAmount_ > 0, "Invalid amount");
    require(minAmount_ <= maxAmount_, "Min less than max");
    require(
      bigWinProb_ + winProb_ + loseProb_ + noImpactProb_ == 10000,
      "Probability should add up to 10000"
    );

    house = house_;

    minAmount = minAmount_.toUint128();
    maxAmount = maxAmount_.toUint128();

    bigWinProb = bigWinProb_.toUint64();
    winProb = winProb_.toUint64();
    loseProb = loseProb_.toUint64();
    noImpactProb = noImpactProb_.toUint64();

    firstJackpotTicket = 0;
  }

  modifier isValidGame(uint256 amount) {
    require(tx.origin == msg.sender, "Player addresses only");
    require(gameOpened, "Game is not opened");
    require(amount >= minAmount, "Amount too low");
    require(amount <= maxAmount, "Amount too high");
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    GAME FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice submits a bet
   * @param amount amount of PLY to bet
   * @dev emits a BetMade event
   */
  function makeBetOnce(uint256 amount) external isValidGame(amount) returns (Outcome) {
    ply.safeTransferFrom(msg.sender, address(this), amount);
    return _makeSingleBet(msg.sender, amount);
  }

  /**
   * @notice settles the current jackpot
   * @dev if there is no tickets, both return values are 0, and no event emitted
   */
  function settleJackpot() external onlyHouse returns (address winner, uint256 amount) {
    winner = _getJackpotWinner();
    amount = 0;

    if (winner != address(0)) {
      amount = currentJackpotAmount;
      currentJackpotAmount = 0;
      ply.safeTransfer(winner, amount);

      firstJackpotTicket = games.length;

      jackpotHistory.push(JackpotHistory(winner, amount));
      emit JackpotWinner(winner, amount);
    }
  }

  /*///////////////////////////////////////////////////////////////
                    SDK AND BACKEND
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice returns how many games the player has made
   */
  function getGameCount(address player) external view returns (uint256) {
    return pastBlocks[player].length;
  }

  /**
   * @notice returns the smallest block `lastBlock`, such that in blocks
   * [lastBlock; current], there are at most `gameCount` games made by `player`
   * @dev If `player` has not made any games, returns 0
   * @dev If `player` has made no more than `gameCount` games, returns the player's first game block
   */
  function getLastBlock(address player, uint256 gameCount)
    external
    view
    returns (uint256 lastBlock)
  {
    if (pastBlocks[player].length == 0) {
      return 0;
    } else if (pastBlocks[player].length <= gameCount) {
      return pastBlocks[player][0];
    } else {
      uint256 len = pastBlocks[player].length;
      return pastBlocks[player][len - gameCount - 1] + 1;
    }
  }

  /*///////////////////////////////////////////////////////////////
                    INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

  function _makeSingleBet(address player, uint256 amount) internal returns (Outcome outcome) {
    // generates and settles outcome
    outcome = _getSingleOutcome();
    _settleSingleOutcome(player, amount, outcome);

    // add this player to the jackpot drawings
    uint256 prevTotal = (games.length == 0 ? 0 : games[games.length - 1].cumulativeAmount);
    games.push(Game(player, outcome, amount.toUint128(), (prevTotal + amount).toUint128()));

    // save this block number
    pastBlocks[player].push(block.number);

    // emit event
    emit BetMade(player, amount, outcome);
  }

  /**
   * @notice generates a single outcome
   * 0 for big win, 1 for win, 2 for lose, 3 for no impact
   */
  function _getSingleOutcome() internal returns (Outcome outcome) {
    uint256 rng = randRange(0, bigWinProb + winProb + loseProb + noImpactProb, false);

    if (rng < bigWinProb) {
      outcome = Outcome.BigWin;
    } else if (rng < bigWinProb + winProb) {
      outcome = Outcome.Win;
    } else if (rng < bigWinProb + winProb + loseProb) {
      outcome = Outcome.Lose;
    } else {
      outcome = Outcome.NoImpact;
    }
  }

  /// @notice takes the necessary actions for a single bet
  function _settleSingleOutcome(
    address player,
    uint256 amount,
    Outcome outcome
  ) internal {
    if (outcome == Outcome.BigWin) {
      ply.safeTransfer(player, amount);
      totalPlyUnlockedEarly[player] += amount * 10;
    } else if (outcome == Outcome.Win) {
      ply.safeTransfer(player, amount);
      totalPlyUnlockedEarly[player] += amount;
    } else if (outcome == Outcome.Lose) {
      currentJackpotAmount += amount;
    } else {
      // no impact
      uint256 jp = amount / 50;
      currentJackpotAmount += jp;
      ply.safeTransfer(player, amount - jp);
    }
  }

  /// @notice finds a jackpot winner, out of all games that were not counted for a jackpot draw yet
  function _getJackpotWinner() internal returns (address winner) {
    if (firstJackpotTicket == games.length) {
      // there has been no more jackpot tickets since last draw
      return address(0);
    }

    uint256 lo = firstJackpotTicket;
    uint256 hi = games.length - 1;

    uint256 prevTotal = (lo == 0 ? 0 : games[lo - 1].cumulativeAmount);
    uint256 curTotal = games[hi - 1].cumulativeAmount; // guaranteed can't be 0
    uint256 nthPLYwinner = randRange(prevTotal, curTotal, true);

    // finds the first index with cumulativeAmount strictly larger than "nthPLYwinner"
    while (lo < hi) {
      uint256 mid = (lo + hi) / 2;

      if (games[mid].cumulativeAmount > nthPLYwinner) {
        // possibly the winner
        hi = mid;
      } else {
        // definitely not the winner
        lo = mid + 1;
      }
    }
    return games[lo].player;
  }

  /*///////////////////////////////////////////////////////////////
                    GOVERNANCE
    //////////////////////////////////////////////////////////////*/

  /// @notice Opens or closes game
  function setOpenState(bool state) external onlyHouse {
    gameOpened = state;
    emit GameOpened(gameOpened);
  }

  /// @notice updates block that unlock was last fetched
  function updateUnlockFetched(uint256 blockNum) external onlyOwner {
    lastUnlockFetch = blockNum;
  }

  /// @notice the house funds jackpot with some amount
  function fundJackpot(uint256 amount) external onlyHouse {
    currentJackpotAmount += amount;
    ply.safeTransferFrom(owner, address(this), amount);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
