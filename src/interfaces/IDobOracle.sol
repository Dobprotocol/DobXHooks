// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDobOracle {
    function nav() external view returns (uint256);
    function defaultRisk() external view returns (uint256);
}
