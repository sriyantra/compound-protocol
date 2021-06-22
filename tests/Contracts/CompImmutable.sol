pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../contracts/Governance/Comp.sol";

contract CompImmutable is Comp {
     constructor(address admin) public {
        initialize(admin, admin);
    }
}
