pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20PluginDelegate.sol";

contract CErc20PluginRewardsDelegate is CErc20PluginDelegate {
        /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes calldata data) external {
        require(msg.sender == address(this) || hasAdminRights());

        (address _plugin, address _rewardsDistributor) = abi.decode(
            data,
            (address, address)
        );

        require(address(plugin) == address(0), "plugin");
        plugin = IPlugin(_plugin);

        EIP20Interface(plugin.rewardToken()).approve(_rewardsDistributor, uint256(-1));
    
        EIP20Interface(underlying).approve(_plugin, uint256(-1));
    }
}