pragma solidity ^0.5.16;

import "./CToken.sol";
import "./ExponentialNoError.sol";
import "./ComptrollerStorage.sol";
import "./IveRGT.sol";
import "./IFuseGaugeController.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./EIP20Interface.sol";
import "./RewardsDistributor.sol";
import "./ReentrancyGuard.sol";

contract FuseBorrowGauge is ReentrancyGuard {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // Instances
    IveRGT private veRGT;
    IFuseGaugeController public gaugeController;
    RewardsDistributor public rewardsDistributor;
    CToken public cToken;

    // Admin address
    address public admin;

    // Constant for various precisions
    uint256 private constant MULTIPLIER_PRECISION = 1e18;

    // Reward and period related
    uint256 private periodFinish;
    uint256 private lastUpdateTime;
    uint256 public reward_rate_manual;
    uint256 public rewardsDuration = 604800; // 7 * 86400  (7 days)

    // Rewards tracking
    uint256 private rewardPerTokenStored;
    mapping(address => uint256) private userRewardPerTokenPaid;
    mapping(address => uint256) private rewards;

    uint256 private _totalSupply;
    uint public derivedSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint) private _base;

    uint256 private last_gauge_relative_weight;
    uint256 private last_gauge_time_total;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _cToken_address,
        address _rewardsDistributor_address,
        address _veRGT_address
    ) public {
        admin = msg.sender;
        cToken = CToken(_cToken_address);
        rewardsDistributor = RewardsDistributor(_rewardsDistributor_address);
        veRGT = IveRGT(_veRGT_address);

        // Manual reward rate
        reward_rate_manual = 0;

        // Initialize
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
    }

    /* ========== VIEWS ========== */
    function totalSupply() external view returns (uint256) {
        return cToken.totalSupply();
    }

    function balanceOf(address account) external view returns (uint256) {
        return cToken.balanceOf(account);
    }

    /**
     * @notice Get rewards boost multiplier for account, based on amount of 
     * veRGT the user holds, up to max boost
     * @param account the account which is being queried 
     * @dev earned weight is calculated: default boost is 1x
     * rewards and max boost factor is 2.5x rewards
     * Example: There are 1,000 veRGT total and 10,000 supply of CTokens.
     * User A has 0 veRGT and 1,000 CTokens for this gauge's market --> BF = 0.4 --> 0.4/0.4 = 1x boost
     * User B has 100 veRGT and 1,000 CTokens --> BF = 1 --> 1/0.4 = 2.5x boost
     */
    function getBoostMultiplier(address account) public view returns (uint256) {
        uint derivedBalance = derivedBalance(account);
        return ((derivedBalance * MULTIPLIER_PRECISION) / cToken.balanceOf(account));
    }

    function derivedBalance(address account) public view returns (uint) {
        if (veRGT.totalSupply() == 0) return 0;
        uint _balance = cToken.balanceOf(account);
        uint _derived = _balance.mul(40).div(100);
        uint _adjusted = (cToken.totalSupply().mul(veRGT.balanceOf(account)).div(veRGT.totalSupply())).mul(60).div(100);
        return Math.min(_derived.add(_adjusted), _balance);
    }

    function lastTimeRewardApplicable() internal view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }
    
    function rewardRate() public view returns (uint256 rwd_rate) {
        if (address(gaugeController) != address(0)) {
            rwd_rate = (gaugeController.global_emission_rate()).mul(last_gauge_relative_weight).div(1e18);
        }
        else {
            rwd_rate = reward_rate_manual;
        }
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate().mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // Two different getReward functions are needed because of delegateCall and msg.sender issues (important for migration)
    function getReward() external nonReentrant returns (uint256) {
        sync(false);
        rewardsDistributor.claimRewards(msg.sender);
    }

    function sync(bool force_update) public {
        if (address(gaugeController) != address(0) && (force_update || (block.timestamp > last_gauge_time_total))) {
            // Update the gauge_relative_weight
            last_gauge_relative_weight = gaugeController.gauge_relative_weight_write(address(this), block.timestamp);
            last_gauge_time_total = gaugeController.time_total();
            rewardsDistributor._setCompBorrowSpeed(address(this));
        }
    }
}