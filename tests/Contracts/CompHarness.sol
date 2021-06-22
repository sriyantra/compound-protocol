pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CompImmutable.sol";

contract CompScenario is CompImmutable {
    constructor(address account) CompImmutable(account) public {}

    function transferScenario(address[] calldata destinations, uint256 amount) external returns (bool) {
        for (uint i = 0; i < destinations.length; i++) {
            address dst = destinations[i];
            _transfer(msg.sender, dst, amount);
            _moveDelegates(delegates[msg.sender], delegates[dst], safe96(amount, "CompScenario::transferScenario: amount exceeds 96 bits"));
        }
        return true;
    }

    function transferFromScenario(address[] calldata froms, uint256 amount) external returns (bool) {
        for (uint i = 0; i < froms.length; i++) {
            address from = froms[i];
            _transfer(from, msg.sender, amount);
            _moveDelegates(delegates[from], delegates[msg.sender], safe96(amount, "CompScenario::transferFromScenario: amount exceeds 96 bits"));
        }
        return true;
    }

    function generateCheckpoints(uint count, uint offset) external {
        for (uint i = 1 + offset; i <= count + offset; i++) {
            checkpoints[msg.sender][numCheckpoints[msg.sender]++] = Checkpoint(uint32(i), uint96(i));
        }
    }
}
