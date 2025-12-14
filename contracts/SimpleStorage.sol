// SPDX-License-Identifier: MIT
// This license is required by Solidity standards.
pragma solidity ^0.8.0;

/**
 * @title SimpleStorage
 * @dev A basic contract to store and retrieve a single number on the blockchain.
 */
contract SimpleStorage {
    // 1. STATE VARIABLE: This data is stored permanently on the blockchain.
    // 'uint256' means an unsigned integer up to 256 bits (a massive number).
    // 'private' means the variable can only be accessed within this contract.
    uint256 private storedData;

    // 2. VIEW FUNCTION (Read-Only):
    // 'public' means anyone can call it.
    // 'view' means it only reads the state; it does NOT cost any gas to run off-chain.
    // 'returns' specifies the output type.
    function retrieve() public view returns (uint256) {
        return storedData;
    }

    // 3. TRANSACTION FUNCTION (Write Operation):
    // 'public' means anyone can call it.
    // This function CHANGES the state of the blockchain (updates storedData).
    // It MUST be executed via a transaction, which costs gas.
    function store(uint256 _data) public {
        // We use an underscore convention (like `_data`) to differentiate function arguments
        // from state variables (like `storedData`).
        storedData = _data;
    }
}