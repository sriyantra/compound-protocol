pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

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

    function transferPlugin(address newPlugin) external;
}