pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20Delegate.sol";
import "./EIP20Interface.sol";

// Ref: https://github.com/backstop-protocol/dev/blob/main/packages/contracts/contracts/B.Protocol/BAMM.sol
interface IBAMM {

    // Views

    function fetchPrice() external view returns (uint256);

    function getSwapEthAmount(uint256 lusdQty) external view returns (uint256 ethAmount, uint256 feeEthAmount);

    function LUSD() external view returns (EIP20Interface);

    function SP() external view returns (IStabilityPool);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    // Reward token
    function bonus() external view returns (address);

    // Mutative Functions

    function deposit(uint256 lusdAmount) external;

    function withdraw(uint256 numShares) external;

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
 */
contract CLusdDelegate is CErc20Delegate {
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

    uint256 constant public PRECISION = 1e18;

    /**
     * @notice Container for SP staking rewards state
     * @member balance The balance of Lqty reward
     * @member index The last updated index
     */
    struct SPRewardState {
        uint256 balance;
        uint256 index;
    }

    /**
     * @notice The state of SP supply
     */
    SPRewardState public spSupplyState;

    /**
     * @notice The index of every SP supplier
     */
    mapping(address => uint256) public spSupplierIndex;

    /**
     * @notice The Lqty amount of every user
     */
    mapping(address => uint256) public lqtyUserAccrued;

    /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes calldata data) external {
        require(msg.sender == address(this) || hasAdminRights(), "only self or admin may call _becomeImplementation");

        (address _bamm, address _lusdSwapper) = abi.decode(
            data,
            (address, address)
        );
        BAMM = IBAMM(_bamm);
        lusdSwapper = ILUSDSwapper(_lusdSwapper);

        lqty = BAMM.bonus();
        stabilityPool = BAMM.SP();

        require(address(BAMM.LUSD()) == underlying, "mismatch underlying token");

        // Approve moving our LUSD into the BAMM rewards contract.
        EIP20Interface(underlying).approve(address(BAMM), uint256(-1));
    }

    /**
     * @notice Manually claim staking rewards by user
     * @return The amount of Lqty rewards user claims
     */
    function claimLqty(address account) public returns (uint256) {
        claimReward();

        updateSPSupplyIndex();
        updateSupplierIndex(account);

        // Get user's Lqty accrued
        uint256 userLqtyBalance = lqtyUserAccrued[account];

        if (userLqtyBalance > 0) {
            // Subtract user Lqty amount from spSupplyState
            spSupplyState.balance = sub_(spSupplyState.balance, userLqtyBalance);

            EIP20Interface(lqty).transfer(account, userLqtyBalance);
            
            // Clear user's Lqty accrued.
            lqtyUserAccrued[account] = 0;

            return userLqtyBalance;
        }
        return 0;
    }

    /*** CToken Overrides ***/

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint256 tokens
    ) internal returns (uint256) {
        claimReward();

        updateSPSupplyIndex();
        updateSupplierIndex(src);
        updateSupplierIndex(dst);

        return super.transferTokens(spender, src, dst, tokens);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint256) {
        EIP20Interface token = EIP20Interface(underlying);
        uint256 heldSupply = token.balanceOf(address(this));
        
        // proportional amount of BAMM LUSD held by this contract
        uint256 depositedSupply = bammLusdValue() * BAMM.balanceOf(address(this)) / BAMM.totalSupply();
        return heldSupply + depositedSupply;
    }

    function bammLusdValue() internal view returns (uint256) {
        return stabilityPool.getCompoundedLUSDDeposit(address(BAMM));
    }

    /**
     * @notice Transfer the underlying to this contract and sweep into rewards contract
     * @param from Address to transfer funds from
     * @param amount Amount of underlying to transfer
     * @param isNative The amount is in native or not
     * @return The actual amount that is transferred
     */
    function doTransferIn(
        address from,
        uint256 amount,
        bool isNative
    ) internal returns (uint256) {
        isNative; // unused

        // Perform the EIP-20 transfer in
        EIP20Interface token = EIP20Interface(underlying);
        require(token.transferFrom(from, address(this), amount), "unexpected EIP-20 transfer in return");

        // Deposit to BAMM
        // LUSD balance used to include any dust
        BAMM.deposit(token.balanceOf(address(this)));

        updateSPSupplyIndex();
        updateSupplierIndex(from);

        return amount;
    }

    /**
     * @notice Transfer the underlying from this contract, after sweeping out of master chef
     * @param to Address to transfer funds to
     * @param amount Amount of underlying to transfer
     * @param isNative The amount is in native or not
     */
    function doTransferOut(
        address payable to,
        uint256 amount,
        bool isNative
    ) internal {
        isNative; // unused

        uint256 totalSupply = BAMM.totalSupply();
        uint256 lusdValue = bammLusdValue();
        uint256 shares = amount * totalSupply / lusdValue;

        // Swap surplus BAMM ETH out for LUSD
        handleETH(lusdValue);

        // Withdraw the LUSD from BAMM
        BAMM.withdraw(shares);

        // Send all held ETH to lusd swapper. Intentionally no failure check, because failure should not block withdrawal
        address(lusdSwapper).call.value(address(this).balance)("");

        updateSPSupplyIndex();
        updateSupplierIndex(to);

        EIP20Interface token = EIP20Interface(underlying);
        require(token.transfer(to, amount), "unexpected EIP-20 transfer out return");
    }

    /**
     * If BAMM ETH amount is below ratio, send to LUSD swapper, otherwise force LUSD swapper to swap for surplus ETH
     */
    function handleETH(uint256 lusdTotal) internal {
        uint256 ethTotal = stabilityPool.getDepositorETHGain(address(BAMM));

        uint256 eth2usdPrice = BAMM.fetchPrice();
        uint256 ethUsdValue = mul_(ethTotal, eth2usdPrice) / PRECISION;

        // TODO make this logic more configurable
        if (lusdTotal < ethUsdValue * 10000) {
            lusdSwapper.swapLUSD(ethUsdValue, ethTotal);
        }
    }

    /*** Internal functions ***/

    function claimReward() internal {
        // Withdrawing 0 claims all LQTY rewards without affecting additional state
        BAMM.withdraw(0);
    }

    function updateSPSupplyIndex() internal {
        uint256 lqtyBalance = lqtyBalance();
        uint256 lqtyAccrued = sub_(lqtyBalance, spSupplyState.balance);
        uint256 supplyTokens = CToken(address(this)).totalSupply();
        Double memory ratio = supplyTokens > 0 ? fraction(lqtyAccrued, supplyTokens) : Double({mantissa: 0});
        Double memory index = add_(Double({mantissa: spSupplyState.index}), ratio);

        // Update spSupplyState
        spSupplyState.index = index.mantissa;
        spSupplyState.balance = lqtyBalance;
    }

    function updateSupplierIndex(address supplier) internal {
        Double memory supplyIndex = Double({mantissa: spSupplyState.index});
        Double memory supplierIndex = Double({mantissa: spSupplierIndex[supplier]});
        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        if (deltaIndex.mantissa > 0) {
            uint256 supplierTokens = CToken(address(this)).balanceOf(supplier);
            uint256 supplierDelta = mul_(supplierTokens, deltaIndex);
            lqtyUserAccrued[supplier] = add_(lqtyUserAccrued[supplier], supplierDelta);
            spSupplierIndex[supplier] = supplyIndex.mantissa;
        }
    }

    function lqtyBalance() internal view returns (uint256) {
        return EIP20Interface(lqty).balanceOf(address(this));
    }
}