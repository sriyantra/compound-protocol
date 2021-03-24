pragma solidity ^0.5.16;

import "./JumpRateModel.sol";
import "./SafeMath.sol";

/**
  * @title Fuse's AlchemixInterestRateModel Contract
  * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
  * @notice Modified version of JumpRateModel in which the kink point is tethered to the ALCX staking APR.
  */
contract AlchemixInterestRateModel is JumpRateModel {
    using SafeMath for uint;

    StakingPools stakingPools;
    uint256 poolId;

    /**
     * @notice Construct an interest rate model
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     * @param stakingPools_ The address of the Alchemix StakingPools contract
     */
    constructor(uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_, address stakingPools_, uint256 poolId_) JumpRateModel(0, multiplierPerYear, jumpMultiplierPerYear, kink_) public {
        stakingPools = StakingPools(stakingPools_);
        poolId = poolId_;
        poke();
    }

    /**
     * @notice Calculates the pool reward rate per block
     * @return The pool reward rate per block (as a percentage, and scaled by 1e18)
     */
    function prrPerBlock() public view returns (uint) {
        return stakingPools.getPoolRewardRate(poolId).mul(1e18).div(stakingPools.getPoolTotalDeposited(poolId));
    }

    /**
     * @notice Resets the baseRate and multiplier per block based on the stability fee and Dai savings rate
     */
    function poke() public {
        // Set baseRatePerBlock so kink point APR = ALCX staking APR
        // baseRatePerBlock + (multiplierPerBlock * kink / 1e18) = ALCX staking APR
        // baseRatePerBlock = ALCX staking APR - (multiplierPerBlock * kink / 1e18)
        uint256 _baseRatePerBlock = prrPerBlock().sub(multiplierPerBlock.mul(kink).div(1e18));

        if (_baseRatePerBlock != baseRatePerBlock) {
            baseRatePerBlock = _baseRatePerBlock;
            emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
        }
    }
}


/*** Alchemix Interfaces ***/

/// @title StakingPools
//    ___    __        __                _               ___                              __         _ 
//   / _ |  / / ____  / /  ___   __ _   (_) __ __       / _ \  ____ ___   ___ ___   ___  / /_  ___  (_)
//  / __ | / / / __/ / _ \/ -_) /  ' \ / /  \ \ /      / ___/ / __// -_) (_-</ -_) / _ \/ __/ (_-< _   
// /_/ |_|/_/  \__/ /_//_/\__/ /_/_/_//_/  /_\_\      /_/    /_/   \__/ /___/\__/ /_//_/\__/ /___/(_)  
//  
//      _______..___________.     ___       __  ___  __  .__   __.   _______    .______     ______     ______    __           _______.
//     /       ||           |    /   \     |  |/  / |  | |  \ |  |  /  _____|   |   _  \   /  __  \   /  __  \  |  |         /       |
//    |   (----``---|  |----`   /  ^  \    |  '  /  |  | |   \|  | |  |  __     |  |_)  | |  |  |  | |  |  |  | |  |        |   (----`
//     \   \        |  |       /  /_\  \   |    <   |  | |  . `  | |  | |_ |    |   ___/  |  |  |  | |  |  |  | |  |         \   \    
// .----)   |       |  |      /  _____  \  |  .  \  |  | |  |\   | |  |__| |    |  |      |  `--'  | |  `--'  | |  `----..----)   |   
// |_______/        |__|     /__/     \__\ |__|\__\ |__| |__| \__|  \______|    | _|       \______/   \______/  |_______||_______/                                                                                                                                
///
/// @dev A contract which allows users to stake to farm tokens.
///
/// This contract was inspired by Chef Nomi's 'MasterChef' contract which can be found in this
/// repository: https://github.com/sushiswap/sushiswap.
interface StakingPools {
  /// @dev Gets the total amount of funds staked in a pool.
  ///
  /// @param _poolId the identifier of the pool.
  ///
  /// @return the total amount of staked or deposited tokens.
  function getPoolTotalDeposited(uint256 _poolId) external view returns (uint256);

  /// @dev Gets the amount of tokens per block being distributed to stakers for a pool.
  ///
  /// @param _poolId the identifier of the pool.
  ///
  /// @return the pool reward rate.
  function getPoolRewardRate(uint256 _poolId) external view returns (uint256);
}
