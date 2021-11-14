pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20Delegate.sol";
import "./EIP20Interface.sol";

interface IBAMMRouter {

    // Views
    function lqty() external view returns(address);

    /// @notice amount of LUSD deposited into stability pool
    function depositedSupply() external view returns(uint256);

    // Mutative Functions

    /// @notice deposit LUSD in BAMM
    function deposit(uint256 lusdAmount) external;

    /// @notice withdraw lusd from BAMM
    function withdraw(address payable to, uint256 lusdAmount) external;

    /// @notice claim LQTY
    function claim() external;
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

    /**
     * @notice B. Protocol BAMM address
     */
    IBAMMRouter public bammRouter;

    uint256 constant public PRECISION = 1e18;
    
    /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes calldata data) external {
        require(msg.sender == address(this) || hasAdminRights(), "admin");

        (address _bamm, address _rewardsDistributor) = abi.decode(
            data,
            (address, address)
        );

        bammRouter = IBAMMRouter(_bamm);

        // Approve rewards distributor to pull LQTY
        EIP20Interface(bammRouter.lqty()).approve(address(_rewardsDistributor), uint256(-1));
    }

    /*** CToken Overrides ***/

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint256) {
        EIP20Interface token = EIP20Interface(underlying);
        uint256 heldSupply = token.balanceOf(address(bammRouter));
        
        return heldSupply + bammRouter.depositedSupply();
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
        require(token.transferFrom(from, address(bammRouter), amount), "send fail");

        return amount;
    }

    /**
     * @notice Transfer the underlying from this contract
     * @param to Address to transfer funds to
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal {
        bammRouter.withdraw(to, amount);
    }
}