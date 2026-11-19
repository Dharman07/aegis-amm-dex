// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract AMMTimelock is TimelockController {
    error ZeroMinDelay();
    error ZeroAdminAddress();

    constructor(uint256 minDelay_, address admin_)
        TimelockController(minDelay_, new address[](0), new address[](0), admin_)
    {
        if (minDelay_ == 0) {
            revert ZeroMinDelay();
        }

        if (admin_ == address(0)) {
            revert ZeroAdminAddress();
        }
    }
}
