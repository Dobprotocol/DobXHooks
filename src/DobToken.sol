// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DobToken
/// @notice ERC20 token representing tokenized RWA revenue streams
/// @dev Only the hook contract can mint and burn tokens
contract DobToken is ERC20, Ownable {
    address public immutable hook;

    error OnlyHook();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(address _hook) ERC20("Dob Solar Farm 2035", "DOB-35") Ownable(msg.sender) {
        hook = _hook;
    }

    /// @notice Mint new tokens (only callable by hook)
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external onlyHook {
        _mint(to, amount);
    }

    /// @notice Burn tokens from an address (only callable by hook)
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn
    function burnFrom(address from, uint256 amount) external onlyHook {
        _burn(from, amount);
    }
}
