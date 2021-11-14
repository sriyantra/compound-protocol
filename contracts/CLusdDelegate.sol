pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20Delegate.sol";
import "./EIP20Interface.sol";

// Ref: https://github.com/backstop-protocol/dev/blob/main/packages/contracts/contracts/B.Protocol/BAMM.sol
interface IBAMM {

    // Views

    /// @notice returns ETH price scaled by 1e18
    function fetchPrice() external view returns (uint256);

    /// @notice returns amount of ETH received for an LUSD swap
    function getSwapEthAmount(uint256 lusdQty) external view returns (uint256 ethAmount, uint256 feeEthAmount);

    /// @notice LUSD token address
    function LUSD() external view returns (EIP20Interface);

    /// @notice Liquity Stability Pool Address
    function SP() external view returns (IStabilityPool);

    /// @notice BAMM shares held by user
    function balanceOf(address account) external view returns (uint256);

    /// @notice total BAMM shares
    function totalSupply() external view returns (uint256);

    /// @notice Reward token
    function bonus() external view returns (address);

    // Mutative Functions

    /// @notice deposit LUSD for shares in BAMM
    function deposit(uint256 lusdAmount) external;

    /// @notice withdraw shares  in BAMM for LUSD + ETH
    function withdraw(uint256 numShares) external;

    /// @notice swap LUSD to ETH in BAMM
    function swap(uint256 lusdAmount, uint256 minEthReturn, address dest) external returns(uint256);
}

// Ref: https://github.com/backstop-protocol/dev/blob/main/packages/contracts/contracts/StabilityPool.sol
interface IStabilityPool {
    function getCompoundedLUSDDeposit(address holder) external view returns(uint256 lusdValue);
    
    function getDepositorETHGain(address holder) external view returns(uint256 ethValue);
}

interface ILUSDSwapper {
    function swapLUSD(uint256 lusdAmount, uint256 minEthReturn) external;
}

/**
 * @title Rari's CLusd's Contract
 * @notice CToken which wraps LUSD B. Protocol deposit
 * @author Joey Santoro
 *
 * CLusdDelegate deposits unborrowed LUSD into the Liquity Stability pool via B. Protocol BAMM
 * The BAMM compounds LUSD deposits by selling ETH into LUSD as the stability pool is utilized.
 * Note that there can still be some ETH as the BAMM does not force convert all ETH.
 * 
 * Any existing ETH withdrawn from BAMM will be either:
 *   1. Swapped for LUSD by lusdSwapper if > 0.01% of the pool value
 *   2. Sent to lusdSwapper is < 0.01% of the pool value
 *
 * LQTY rewards accrue proportionally to depositors
 */
contract CLusdDelegate is CErc20Delegate {

    event ClaimRewards(address indexed user, uint256 lqtyAmount);

    event LusdSwap(address indexed lusdSwapper, uint256 lusdAmount, uint256 minEthAmount);

    /**
     * @notice Liquity Stability Pool address
     */
    IStabilityPool public stabilityPool;

    /**
     * @notice LUSD swapper address
     */
    ILUSDSwapper public lusdSwapper;

    /**
     * @notice B. Protocol BAMM address
     */
    IBAMM public BAMM;

    /**
     * @notice Lqty token address
     */
    address public lqty;

    /// @notice buffer is the target percentage of LUSD deposits to remaing outside stability pool
    uint256 public buffer;

    uint256 constant public PRECISION = 1e18;

    /// @notice minimum swap amount for the lusdSwapper to perform a swap
    uint256 public ethSwapMin;

    function () external payable {} // contract should be able to receive ETH
    
    /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes calldata data) external {
        require(msg.sender == address(this) || hasAdminRights(), "admin");

        (address _bamm, address _lusdSwapper, uint256 _buffer, uint256 _ethSwapMin, address _rewardsDistributor) = abi.decode(
            data,
            (address, address, uint256, uint256, address)
        );
        BAMM = IBAMM(_bamm);
        lusdSwapper = ILUSDSwapper(_lusdSwapper);

        buffer = _buffer;
        ethSwapMin = _ethSwapMin;

        lqty = BAMM.bonus(); // Set lqty to BAMM reward token
        stabilityPool = BAMM.SP();

        require(address(BAMM.LUSD()) == underlying, "mismatch token");

        // Approve moving our LUSD into the BAMM rewards contract.
        EIP20Interface(underlying).approve(address(BAMM), uint256(-1));

        // Approve rewards distributor to pull LQTY
        EIP20Interface(lqty).approve(address(_rewardsDistributor), uint256(-1));
    }

    /*** CToken Overrides ***/

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint256) {
        EIP20Interface token = EIP20Interface(underlying);
        uint256 heldSupply = token.balanceOf(address(this));
        
        return heldSupply + depositedSupply();
    }

    // proportional amount of BAMM LUSD held by this contract
    function depositedSupply() internal view returns (uint256) {
        uint256 bammLusdValue = stabilityPool.getCompoundedLUSDDeposit(address(BAMM));
        return bammLusdValue * BAMM.balanceOf(address(this)) / BAMM.totalSupply();
    }

    /**
     * @notice Transfer the underlying to this contract and sweep into rewards contract
     * @param from Address to transfer funds from
     * @param amount Amount of underlying to transfer
     * @return The actual amount that is transferred
     */
    function doTransferIn(
        address from,
        uint256 amount
    ) internal returns (uint256) {
        // Perform the EIP-20 transfer in
        EIP20Interface token = EIP20Interface(underlying);
        require(token.transferFrom(from, address(this), amount), "send fail");

        uint256 heldBalance = token.balanceOf(address(this));

        uint256 depositedBalance = depositedSupply();

        uint256 targetHeld = mul_(add_(depositedBalance, heldBalance), buffer) / PRECISION;

        if (heldBalance > targetHeld) {
            // Deposit to BAMM
            BAMM.deposit(sub_(heldBalance, targetHeld));
        }

        return amount;
    }

    /**
     * @notice Transfer the underlying from this contract, after sweeping out of master chef
     * @param to Address to transfer funds to
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal {
        EIP20Interface token = EIP20Interface(underlying);

        uint256 heldBalance = token.balanceOf(address(this));

        if (amount > heldBalance) {
            uint256 lusdNeeded = amount - heldBalance;

            uint256 totalSupply = BAMM.totalSupply();
            uint256 lusdValue = stabilityPool.getCompoundedLUSDDeposit(address(BAMM));
            uint256 shares = mul_(lusdNeeded, totalSupply) / lusdValue;

            // Swap surplus BAMM ETH out for LUSD
            handleETH(lusdValue);

            // Withdraw the LUSD from BAMM
            BAMM.withdraw(shares);

            // Send all held ETH to lusd swapper. Intentionally no failure check, because failure should not block withdrawal
            address(lusdSwapper).call.value(address(this).balance)("");
        } else {
            BAMM.withdraw(0); // Claim LQTY
            // TODO: should claims happen on transfer or supply?
        }

        require(token.transfer(to, amount), "send fail");
    }

    /**
     * If BAMM ETH amount is below ratio, send to LUSD swapper, otherwise force LUSD swapper to swap for surplus ETH
     */
    function handleETH(uint256 lusdTotal) internal {
        uint256 ethTotal = stabilityPool.getDepositorETHGain(address(BAMM));

        if (ethTotal > ethSwapMin) {
            uint256 eth2usdPrice = BAMM.fetchPrice();
            uint256 ethUsdValue = mul_(ethTotal, eth2usdPrice) / PRECISION;

            lusdSwapper.swapLUSD(ethUsdValue, ethTotal);
            emit LusdSwap(address(lusdSwapper), ethUsdValue, ethTotal);
        }
    }
}