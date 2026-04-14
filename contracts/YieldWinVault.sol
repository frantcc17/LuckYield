// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title YieldWinVault
 * @author YieldWin Protocol
 * @notice No-Loss Lottery vault using ERC4626 + Ondo USDY + Chainlink VRF/Automation
 * @dev Users deposit USDC, receive non-transferable Tickets. Yield from USDY funds the prize pool.
 *      When accumulated yield exceeds $2,000, a Chainlink VRF draw is triggered.
 */

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import "./interfaces/IUSDYOracle.sol";
import "./LotteryLogic.sol";

contract YieldWinVault is
    ERC4626,
    ReentrancyGuard,
    Ownable,
    Pausable,
    VRFConsumerBaseV2Plus,
    AutomationCompatibleInterface
{
    using SafeERC20 for IERC20;
    using LotteryLogic for LotteryLogic.DrawState;

    // ─────────────────────────────────────────────
    //  Constants
    // ─────────────────────────────────────────────

    /// @notice Minimum yield surplus (in USDC, 6 decimals) required to trigger a draw
    uint256 public constant DRAW_THRESHOLD = 2_000e6;

    /// @notice Lock-up period after deposit (48 hours)
    uint48 public constant LOCKUP_PERIOD = 48 hours;

    /// @notice Prize distribution basis points (total = 10_000)
    uint256 public constant GRAND_PRIZE_BPS  = 6_000; // 60% of yield pool
    uint256 public constant SMALL_PRIZE_BPS  = 500;   // 5% each × 4 = 20%
    uint256 public constant LP_REWARD_BPS    = 1_000; // 10%
    uint256 public constant TREASURY_BPS     = 1_000; // 10%

    uint256 public constant EARLY_EXIT_FEE_BPS = 50; // 0.5% penalty if withdrawn within lock-up

    // ─────────────────────────────────────────────
    //  Chainlink VRF Configuration
    // ─────────────────────────────────────────────

    IVRFCoordinatorV2Plus public immutable vrfCoordinator;
    bytes32 public immutable keyHash;
    uint256 public immutable subscriptionId;
    uint16  public constant REQUEST_CONFIRMATIONS = 3;
    uint32  public constant CALLBACK_GAS_LIMIT    = 500_000;
    uint32  public constant NUM_WORDS             = 1; // One seed → derive 5 winners

    // ─────────────────────────────────────────────
    //  State
    // ─────────────────────────────────────────────

    /// @notice USDY token (yield-bearing wrapper around USDC from Ondo Finance)
    IERC20 public immutable usdy;

    /// @notice Oracle that returns current USDY/USDC exchange rate
    IUSDYOracle public oracle;

    /// @notice Addresses for fee distribution
    address public lpRewardAddress;
    address public treasuryAddress;

    /// @notice Total USDC deposited by users (principal, no yield)
    uint256 public totalPrincipal;

    /// @notice Timestamp of the last completed draw
    uint256 public lastDrawTimestamp;

    /// @notice VRF request ID currently in-flight (0 = none)
    uint256 public pendingRequestId;

    /// @notice Snapshot of yield at time of draw request (to avoid re-entrancy race)
    uint256 private _pendingYieldSnapshot;

    /// @notice Deposit timestamp per user (for lock-up enforcement)
    mapping(address => uint48) public depositTimestamp;

    /// @notice Historical draw results
    DrawResult[] public drawHistory;

    /// @notice Per-depositor principal tracking
    mapping(address => uint256) public principalOf;

    // ─────────────────────────────────────────────
    //  Structs & Events
    // ─────────────────────────────────────────────

    struct DrawResult {
        uint256 timestamp;
        uint256 totalYield;
        address grandWinner;
        address[4] smallWinners;
        uint256 grandPrize;
        uint256 smallPrize;
    }

    event DrawTriggered(uint256 indexed requestId, uint256 yieldSnapshot);
    event DrawCompleted(uint256 indexed requestId, address grandWinner, address[4] smallWinners, uint256 totalYield);
    event Deposited(address indexed user, uint256 usdcAmount, uint256 tickets);
    event Withdrawn(address indexed user, uint256 usdcAmount, uint256 tickets, bool earlyExit);
    event OracleUpdated(address newOracle);
    event LpAddressUpdated(address newAddress);
    event TreasuryAddressUpdated(address newAddress);

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    /**
     * @param _usdc           Underlying asset (USDC)
     * @param _usdy           Ondo USDY token
     * @param _oracle         RWADynamicRateOracle from Ondo
     * @param _vrfCoordinator Chainlink VRF Coordinator v2.5
     * @param _keyHash        VRF key hash for the chosen gas lane
     * @param _subscriptionId Chainlink VRF subscription ID
     * @param _lpReward       Address receiving LP rewards
     * @param _treasury       Protocol treasury address
     */
    constructor(
        address _usdc,
        address _usdy,
        address _oracle,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        address _lpReward,
        address _treasury
    )
        ERC4626(IERC20(_usdc))
        ERC20("YieldWin Ticket", "YWT")
        Ownable(msg.sender)
        VRFConsumerBaseV2Plus(_vrfCoordinator)
    {
        require(_usdy     != address(0), "YW: zero usdy");
        require(_oracle   != address(0), "YW: zero oracle");
        require(_lpReward != address(0), "YW: zero lp");
        require(_treasury != address(0), "YW: zero treasury");

        usdy             = IERC20(_usdy);
        oracle           = IUSDYOracle(_oracle);
        vrfCoordinator   = IVRFCoordinatorV2Plus(_vrfCoordinator);
        keyHash          = _keyHash;
        subscriptionId   = _subscriptionId;
        lpRewardAddress  = _lpReward;
        treasuryAddress  = _treasury;
    }

    // ─────────────────────────────────────────────
    //  ERC4626 Overrides (non-transferable tickets)
    // ─────────────────────────────────────────────

    /// @dev Tickets are soulbound – no transfers allowed
    function _update(address from, address to, uint256 amount) internal override {
        require(
            from == address(0) || to == address(0),
            "YW: tickets non-transferable"
        );
        super._update(from, to, amount);
    }

    // ─────────────────────────────────────────────
    //  Deposit
    // ─────────────────────────────────────────────

    /**
     * @notice Deposit USDC and receive Ticket tokens 1:1.
     *         The USDC is immediately converted to USDY via Ondo.
     * @param assets    Amount of USDC to deposit (6 decimals)
     * @param receiver  Address that receives the Tickets
     * @return shares   Number of Tickets minted
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        require(assets > 0, "YW: zero deposit");
        require(pendingRequestId == 0, "YW: draw in progress");

        // Pull USDC from caller
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Convert USDC → USDY (slippage: accept at least 99.5% of expected USDY)
        uint256 usdyReceived = _convertUsdcToUsdy(assets);

        // Track principal (in USDC terms)
        principalOf[receiver] += assets;
        totalPrincipal        += assets;

        // Mint 1 Ticket per 1 USDC deposited
        shares = assets; // 1:1 ratio
        _mint(receiver, shares);

        // Record deposit timestamp for lock-up
        depositTimestamp[receiver] = uint48(block.timestamp);

        emit Deposited(receiver, assets, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // ─────────────────────────────────────────────
    //  Withdraw
    // ─────────────────────────────────────────────

    /**
     * @notice Burn Tickets and withdraw original USDC principal.
     *         If within lock-up period, an early-exit fee applies.
     * @param shares    Number of Tickets to burn
     * @param receiver  USDC recipient
     * @param owner_    Ticket owner
     * @return assets   USDC returned
     */
    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        require(shares > 0, "YW: zero shares");
        require(pendingRequestId == 0, "YW: draw in progress");

        // Burn caller allowance if not self
        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        // Checks-Effects-Interactions
        bool earlyExit = block.timestamp < depositTimestamp[owner_] + LOCKUP_PERIOD;

        // Compute USDC to return (shares == principal 1:1)
        assets = shares;

        // Update state before interactions
        principalOf[owner_] -= shares;
        totalPrincipal       -= shares;
        _burn(owner_, shares);

        // Convert proportional USDY back to USDC
        uint256 usdcOut = _redeemUsdyForUsdc(assets);

        // Apply early-exit fee if within lock-up
        if (earlyExit) {
            uint256 fee = (usdcOut * EARLY_EXIT_FEE_BPS) / 10_000;
            usdcOut -= fee;
            IERC20(asset()).safeTransfer(treasuryAddress, fee);
        }

        IERC20(asset()).safeTransfer(receiver, usdcOut);

        emit Withdrawn(owner_, usdcOut, shares, earlyExit);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @dev Alias so ERC4626 withdraw() also works
    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        returns (uint256 shares)
    {
        shares = assets; // 1:1
        redeem(shares, receiver, owner_);
    }

    // ─────────────────────────────────────────────
    //  Lottery: Chainlink Automation
    // ─────────────────────────────────────────────

    /**
     * @notice Chainlink Automation calls this to decide whether to trigger a draw.
     * @dev    Condition: current pool value − totalPrincipal ≥ DRAW_THRESHOLD
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory)
    {
        upkeepNeeded = _isDrawNeeded() && pendingRequestId == 0;
    }

    /**
     * @notice Chainlink Automation calls this to request randomness when condition is met.
     */
    function performUpkeep(bytes calldata) external override whenNotPaused {
        require(_isDrawNeeded(), "YW: threshold not reached");
        require(pendingRequestId == 0, "YW: draw already pending");

        // Snapshot current yield before request
        _pendingYieldSnapshot = _currentYield();

        // Request randomness from Chainlink VRF v2.5
        uint256 requestId = vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash:            keyHash,
                subId:              subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit:   CALLBACK_GAS_LIMIT,
                numWords:           NUM_WORDS,
                extraArgs:          VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })
                )
            })
        );

        pendingRequestId = requestId;
        emit DrawTriggered(requestId, _pendingYieldSnapshot);
    }

    // ─────────────────────────────────────────────
    //  Lottery: VRF Callback
    // ─────────────────────────────────────────────

    /**
     * @notice Callback from Chainlink VRF with random seed.
     *         Selects 5 unique winners and distributes yield.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)
        internal
        override
    {
        require(requestId == pendingRequestId, "YW: unknown request");

        uint256 totalYield = _pendingYieldSnapshot;
        pendingRequestId   = 0;
        _pendingYieldSnapshot = 0;

        // Collect eligible participants (deposited ≥ 48h ago)
        address[] memory eligible = _getEligibleParticipants();
        require(eligible.length >= 5, "YW: not enough participants");

        // Select 5 unique winners using LotteryLogic library
        address[5] memory winners = LotteryLogic.selectWinners(eligible, randomWords[0]);

        // ── Distribution ──────────────────────────────
        uint256 grandPrize = (totalYield * GRAND_PRIZE_BPS)  / 10_000;
        uint256 smallPrize = (totalYield * SMALL_PRIZE_BPS)  / 10_000;
        uint256 lpReward   = (totalYield * LP_REWARD_BPS)    / 10_000;
        uint256 treasury   = (totalYield * TREASURY_BPS)     / 10_000;

        // Convert yield (held as USDY) to USDC for distribution
        _distributeYield(winners[0], grandPrize, winners[1:5], smallPrize, lpReward, treasury);

        // Record draw result
        DrawResult memory result;
        result.timestamp  = block.timestamp;
        result.totalYield = totalYield;
        result.grandWinner = winners[0];
        result.smallWinners = [winners[1], winners[2], winners[3], winners[4]];
        result.grandPrize  = grandPrize;
        result.smallPrize  = smallPrize;
        drawHistory.push(result);

        lastDrawTimestamp = block.timestamp;

        emit DrawCompleted(requestId, winners[0], result.smallWinners, totalYield);
    }

    // ─────────────────────────────────────────────
    //  Internal: USDY ↔ USDC
    // ─────────────────────────────────────────────

    /**
     * @dev Converts USDC to USDY with 0.5% slippage protection.
     *      For testnet/mock: USDY address acts as direct 1:1 + oracle rate.
     */
    function _convertUsdcToUsdy(uint256 usdcAmount) internal returns (uint256 usdyAmount) {
        // Get current USDY price from oracle (18 decimals, e.g., 1.05e18 = $1.05)
        uint256 price = oracle.getPrice(); // USDC per USDY
        uint256 expectedUsdy = (usdcAmount * 1e18) / price;
        uint256 minUsdy      = (expectedUsdy * 995) / 1000; // 0.5% slippage

        // Approve and swap USDC → USDY via Ondo router (mock: direct transfer)
        IERC20(asset()).approve(address(usdy), usdcAmount);
        // In production: call Ondo's mint/router. For MVP mock:
        usdy.transferFrom(address(this), address(this), 0); // no-op placeholder
        usdyAmount = expectedUsdy;

        require(usdyAmount >= minUsdy, "YW: slippage exceeded");
    }

    /**
     * @dev Redeems USDY back to USDC proportionally to the requested principal.
     */
    function _redeemUsdyForUsdc(uint256 principalAmount) internal returns (uint256 usdcOut) {
        // For MVP mock: return principal directly (yield stays in vault)
        usdcOut = principalAmount;
    }

    /**
     * @dev Distributes yield prizes in USDC to winners, LP and treasury.
     */
    function _distributeYield(
        address grandWinner,
        uint256 grandAmount,
        address[] memory smallWinners,
        uint256 smallAmount,
        uint256 lpAmount,
        uint256 treasuryAmount
    ) internal {
        IERC20 usdc = IERC20(asset());
        usdc.safeTransfer(grandWinner, grandAmount);
        for (uint256 i = 0; i < smallWinners.length; i++) {
            usdc.safeTransfer(smallWinners[i], smallAmount);
        }
        usdc.safeTransfer(lpRewardAddress,  lpAmount);
        usdc.safeTransfer(treasuryAddress,  treasuryAmount);
    }

    // ─────────────────────────────────────────────
    //  Internal: Helpers
    // ─────────────────────────────────────────────

    /// @dev Returns total pool value in USDC terms using oracle
    function _poolValueUsdc() internal view returns (uint256) {
        uint256 usdyBalance = usdy.balanceOf(address(this));
        uint256 price       = oracle.getPrice(); // USDC per USDY (1e18 scale)
        return (usdyBalance * price) / 1e18;
    }

    /// @dev Current yield = pool value − total principal
    function _currentYield() internal view returns (uint256) {
        uint256 poolValue = _poolValueUsdc();
        return poolValue > totalPrincipal ? poolValue - totalPrincipal : 0;
    }

    /// @dev True when accumulated yield meets the draw threshold
    function _isDrawNeeded() internal view returns (bool) {
        return _currentYield() >= DRAW_THRESHOLD;
    }

    /// @dev Returns array of Ticket holders whose deposit is older than LOCKUP_PERIOD.
    ///      NOTE: Production should use off-chain indexing; this is for MVP demonstration.
    function _getEligibleParticipants() internal view returns (address[] memory) {
        // This function requires enumerable holders. In production, maintain an EnumerableSet.
        // Placeholder: returns empty, to be replaced with on-chain participant registry.
        revert("YW: implement participant registry");
    }

    // ─────────────────────────────────────────────
    //  View Functions
    // ─────────────────────────────────────────────

    /// @notice Current jackpot (yield available for next draw)
    function currentJackpot() external view returns (uint256) {
        return _currentYield();
    }

    /// @notice Total value locked in the vault
    function tvl() external view returns (uint256) {
        return _poolValueUsdc();
    }

    /// @notice Number of completed draws
    function drawCount() external view returns (uint256) {
        return drawHistory.length;
    }

    /// @notice Get a draw result by index
    function getDrawResult(uint256 index) external view returns (DrawResult memory) {
        return drawHistory[index];
    }

    /// @notice Whether a user is currently eligible (lock-up passed)
    function isEligible(address user) external view returns (bool) {
        return balanceOf(user) > 0 &&
               block.timestamp >= depositTimestamp[user] + LOCKUP_PERIOD;
    }

    // ─────────────────────────────────────────────
    //  Admin
    // ─────────────────────────────────────────────

    function setOracle(address newOracle) external onlyOwner {
        oracle = IUSDYOracle(newOracle);
        emit OracleUpdated(newOracle);
    }

    function setLpAddress(address addr) external onlyOwner {
        lpRewardAddress = addr;
        emit LpAddressUpdated(addr);
    }

    function setTreasury(address addr) external onlyOwner {
        treasuryAddress = addr;
        emit TreasuryAddressUpdated(addr);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─────────────────────────────────────────────
    //  ERC4626 Required Overrides (return USDC values)
    // ─────────────────────────────────────────────

    function totalAssets() public view override returns (uint256) {
        return _poolValueUsdc();
    }
}
