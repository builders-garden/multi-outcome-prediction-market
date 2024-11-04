// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiOutcomePredictionMarket {
    
    event MarketCreated(uint indexed marketId, string[] optionNames);
    event MarketResolved(uint indexed marketId, uint winningOptionIndex, string winningOptionName);
    event BoughtShares(address indexed user, uint indexed marketId, uint optionId, uint amount, uint totalCost, uint[] prices, uint timestamp);
    event SoldShares(address indexed user, uint indexed marketId, uint optionId, uint amount, uint totalReturn, uint[] prices, uint timestamp);
    event Withdrawal(address indexed user, uint indexed marketId, uint shares, uint reward);

    /**
     * @notice Represents a single option in a prediction market
     * @dev Stores the current state and pricing information for a market option
     */
    struct Option {
        uint256 shares;        /// @notice Total number of shares for this option
        uint256 initialPrice;  /// @notice Initial price set at market creation
        uint256 price;        /// @notice Current price of the option
        string optionName;    /// @notice Human-readable name of the option
    }

    /**
     * @notice Represents a complete prediction market
     * @dev Contains all options and market parameters
     */
    struct Market {
        Option[] options;
        uint256 baseImpactFactor;  /// @notice Base factor for price impact
        uint256 impactPower;       /// @notice Power factor for non-linear impact (scaled by 1e3)
        uint256 winningOptionIndex; 
        uint prizePool;
        bool resolved;
    }

    /**
     * @notice Tracks user's shares in a specific market
     */
    struct UserShares {
        uint[] shares;
        bool claimed;
    }
}