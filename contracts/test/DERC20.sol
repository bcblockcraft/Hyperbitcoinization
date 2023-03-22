// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DERC20 is ERC20 {
    uint8 _decimals;

    constructor(uint8 decimals_) ERC20("TOKEN", "TOKEN") {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
