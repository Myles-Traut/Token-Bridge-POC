// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("Token", "TKN", 18) {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
