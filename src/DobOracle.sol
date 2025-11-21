// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDobOracle} from "./interfaces/IDobOracle.sol";

/// @title DobOracle
/// @notice Simple mock push oracle for NAV and default risk
/// @dev Perfect for hackathon & testing - trusted operator updates values
contract DobOracle is IDobOracle {
    uint256 public nav = 1e18;           // 1.00 USDC per token (18 decimals)
    uint256 public defaultRisk = 1000;   // 10.00% (in bps)

    address public updater;

    event OracleUpdated(uint256 nav, uint256 defaultRisk);

    error OnlyUpdater();

    constructor() {
        updater = msg.sender;
    }

    /// @notice Update NAV and default risk
    /// @param _nav New NAV value (18 decimals)
    /// @param _defaultRisk New default risk in basis points
    function update(uint256 _nav, uint256 _defaultRisk) external {
        if (msg.sender != updater) revert OnlyUpdater();
        nav = _nav;
        defaultRisk = _defaultRisk;
        emit OracleUpdated(_nav, _defaultRisk);
    }

    /// @notice Transfer updater role to new address
    /// @param _newUpdater New updater address
    function setUpdater(address _newUpdater) external {
        if (msg.sender != updater) revert OnlyUpdater();
        updater = _newUpdater;
    }
}
