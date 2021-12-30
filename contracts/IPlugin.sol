pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

interface IPlugin {

    // Views

    function balanceOfUnderlying(address _owner) external view returns (uint256);

    function underlying() external view returns (address);

    // Mutative Functions

    function deposit(address _to, uint256 _value) external returns (uint256 _shares);

    /// @notice withdraw underlying from vault
    function withdraw(address _to, uint256 _value) external returns (uint256 _shares);
}

interface IRewardsPlugin {

    // Views
    function rewardToken() external view returns(address);

    function balanceOfUnderlying(address _owner) external view returns (uint256);

    function underlying() external view returns (address);

    // Mutative Functions

    /// @notice claim reward token
    function claim(address to) external;

    function deposit(address _to, uint256 _value) external returns (uint256 _shares);

    /// @notice withdraw underlying from vault
    function withdraw(address _to, uint256 _value) external returns (uint256 _shares);
}