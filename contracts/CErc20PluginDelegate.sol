pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20Delegate.sol";
import "./EIP20Interface.sol";

interface IPlugin {

    // Views
    function rewardToken() external view returns(address);

    /// @notice amount of underlying token deposited
    function getCash() external view returns(uint256);

    // Mutative Functions

    /// @notice deposit underlying in plugin
    function deposit(uint256 lusdAmount) external;

    /// @notice withdraw underlying from plugin
    function withdraw(address payable to, uint256 lusdAmount) external;

    /// @notice claim reward token
    function claim() external;
}

/**
 * @title Rari's CErc20Plugin's Contract
 * @notice CToken which outsources token logic to a plugin
 * @author Joey Santoro
 *
 * CErc20PluginDelegate deposits and withdraws from a plugin conract
 * It is also capable of delegating reward functionality to a PluginRewardsDistributor
 */
contract CErc20PluginDelegate is CErc20Delegate {

    /**
     * @notice Plugin address
     */
    IPlugin public plugin;

    uint256 constant public PRECISION = 1e18;
    
    /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes calldata data) external {
        require(msg.sender == address(this) || hasAdminRights(), "admin");

        (address _plugin, address _rewardsDistributor) = abi.decode(
            data,
            (address, address)
        );

        plugin = IPlugin(_plugin);

        // Approve rewards distributor to pull reward token
        if (_rewardsDistributor != address(0)) {
            EIP20Interface(plugin.rewardToken()).approve(address(_rewardsDistributor), uint256(-1));
        }
    }

    /*** CToken Overrides ***/

    /*** Safe Token ***/

    /**
     * @notice Gets balance of the plugin in terms of the underlying
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint256) {
        return plugin.getCash();
    }

    /**
     * @notice Transfer the underlying to the plugin and trigger a deposit
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
        require(token.transferFrom(from, address(plugin), amount), "send fail");

        plugin.deposit(amount);
        return amount;
    }

    /**
     * @notice Transfer the underlying from plugin to destination
     * @param to Address to transfer funds to
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal {
        plugin.withdraw(to, amount);
    }
}