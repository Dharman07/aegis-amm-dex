pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract LPToken is ERC20 {

    address public immutable pool;

    error ZeroPoolAddress();
    error UnauthorizedPool(address caller);

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert UnauthorizedPool(msg.sender);
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address pool_
    ) ERC20(name_, symbol_) {
        if (pool_ == address(0)) {
            revert ZeroPoolAddress();
        }

        pool = pool_;
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyPool {
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) external onlyPool {
        _burn(from, amount);
    }

}