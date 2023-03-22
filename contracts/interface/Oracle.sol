// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface Oracle {
    function latestAnswer() external returns (uint256);

    function decimals() external returns (uint8);
}
