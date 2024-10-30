// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/**
 * @title MultiOutcomePredictionMarket
 * @author Original contract enhanced with NatSpec
 * @notice A prediction market contract allowing users to trade shares of different market outcomes
 * @dev Implements a LMSR (Logarithmic Market Scoring Rule) based prediction market with custom impact functions
 */
contract MockUsdc is ERC20 {
    constructor()ERC20("MockUsdc", "mUSDC"){}
}
