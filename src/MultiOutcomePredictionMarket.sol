// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IMultiOutcomePredictionMarket.sol";

/**
 * @title MultiOutcomePredictionMarket
 * @author Original contract enhanced with NatSpec
 * @notice A prediction market contract allowing users to trade shares of different market outcomes
 * @dev Implements a LMSR (Logarithmic Market Scoring Rule) based prediction market with custom impact functions
 */
contract MultiOutcomePredictionMarket is IMultiOutcomePredictionMarket {

    //║══════════════════════════════════════════╗
    //║             Storage                      ║
    //║══════════════════════════════════════════╝

    mapping(uint256 => Market) internal markets;
    mapping(address user => mapping(uint marketId => UserShares sharesInfos)) internal userMarketShares;
    mapping(address => uint) internal userVolume; /// @dev Used for recovery purposes only
    uint256 public marketCount;
    uint256 public constant TOTAL_PRICE = 1e6;
    uint256 public constant IMPACT_POWER_SCALE = 1e3;
    uint256 public constant LINEAR_POWER = 1e3;    /// @dev 1.0 scaled
    uint256 public constant QUADRATIC_POWER = 2e3; /// @dev 2.0 scaled
    uint256 public constant BASE_IMPACT_FACTOR = 100;
    address public  USDC_BASE_SEPOLIA;
    address public admin;
    bool public isEmergencyState;

    /**
     * @notice Contract constructor
     * @param _admin Address of the contract administrator
     */
    constructor(address _admin, address _usdc) {
        admin = _admin;
        USDC_BASE_SEPOLIA = _usdc;
    }

    /**
     * @notice Restricts function access to admin only
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    //║══════════════════════════════════════════╗
    //║    Admin Functions                       ║
    //║══════════════════════════════════════════╝

    /**
     * @notice Creates a new prediction market
     * @dev Initializes a market with given options and pricing model
     * @param initialPrices Array of initial prices for each option
     * @param optionNames Array of names for each option
     * @param isQuadratic Whether to use quadratic or linear price impact
     */
    function createMarket(
        uint256[] memory initialPrices, 
        string[] memory optionNames,
        bool isQuadratic
    ) public onlyAdmin() {
        require(initialPrices.length == optionNames.length, "Prices and names length mismatch");
        require(initialPrices.length > 0, "Must provide initial prices");
        require(initialPrices.length <= 32, "Maximum 32 options allowed");
        
        marketCount++;
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < initialPrices.length; i++) {
            totalPrice += initialPrices[i];
        }
        require(totalPrice == TOTAL_PRICE, "Prices must sum to TOTAL_PRICE");

        Market storage newMarket = markets[marketCount];
        newMarket.impactPower = isQuadratic ? QUADRATIC_POWER : LINEAR_POWER;

        for (uint256 i = 0; i < initialPrices.length; i++) {
            newMarket.options.push(Option(0, initialPrices[i], initialPrices[i], optionNames[i]));
        }   
    }

    /**
     * @notice Enables or disables emergency state
     * @param isEmergency New emergency state
     */
    function declareEmergency(bool isEmergency) external onlyAdmin() {
        isEmergencyState = isEmergency;
    }

    /**
     * @notice Resolves a market by setting the winning option
     * @param marketId ID of the market to resolve
     * @param winningOptionIndex Index of the winning option
     */
    function optimisticMarketResolution(uint marketId, uint winningOptionIndex) public onlyAdmin {
        Market storage market = markets[marketId];
        market.winningOptionIndex = winningOptionIndex;
        market.resolved = true;
    }

    /**
     * @notice Batch resolves multiple markets
     * @param marketIds Array of market IDs to resolve
     * @param winningOptionsIndexes Array of winning option indexes
     */
    function batchOptimisticMarketResolution(uint[] memory marketIds, uint[] memory winningOptionsIndexes) external onlyAdmin {
        for (uint i = 0; i < marketIds.length; ++i) {
            optimisticMarketResolution(marketIds[i], winningOptionsIndexes[i]);
        }
    }

    //║══════════════════════════════════════════╗
    //║    Users Functions                       ║
    //║══════════════════════════════════════════╝

    /**
     * @notice Allows users to buy shares in a market option
     * @param marketId ID of the target market
     * @param optionId ID of the option to buy
     * @param quantity Number of shares to buy
     */
    function buy(uint256 marketId, uint256 optionId, uint256 quantity) public {
        Market storage market = markets[marketId];
        UserShares storage userShares = userMarketShares[msg.sender][marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "quantity must be greater than zero");
        require(!market.resolved, "Market is resolved");
        require(!isEmergencyState, "Contract is paused");
        require(marketId <= marketCount, "Market dosen't exists");

        if (userShares.shares.length == 0) {
            uint[] memory newUserSharesArr = new uint[](market.options.length);
            userShares.shares = newUserSharesArr;
        }

        // Calculate cost BEFORE modifying state
        uint cost = calculateBuyCost(marketId, optionId, quantity);

        // Update state AFTER calculating cost
        market.options[optionId].shares += quantity;
        userShares.shares[optionId] += quantity;
        
        userVolume[msg.sender] += cost;
        market.prizePool += cost;

        IERC20(USDC_BASE_SEPOLIA).transferFrom(msg.sender, address(this), cost);

        _updateMarketPrices(marketId);
    }

    /**
     * @notice Allows users to sell their shares
     * @param marketId ID of the target market
     * @param optionId ID of the option to sell
     * @param quantity Number of shares to sell
     */
    function sell(uint256 marketId, uint256 optionId, uint256 quantity) public {
        Market storage market = markets[marketId];
        UserShares storage userShares = userMarketShares[msg.sender][marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "quantity must be greater than zero");
        require(userShares.shares[optionId] >= quantity, "Not enough shares to sell");
        require(!market.resolved, "Market is resolved");
        require(marketId <= marketCount, "Market dosen't exists");
        market.options[optionId].shares -= quantity;
        uint sellReturn = calculateSellReturn(marketId, optionId, quantity);
        uint sellReturnAfterFees = (sellReturn * 90 / 100);

        userVolume[msg.sender] -= sellReturnAfterFees;
        market.prizePool -= sellReturnAfterFees;

        IERC20(USDC_BASE_SEPOLIA).transfer(msg.sender, sellReturnAfterFees);

        _updateMarketPrices(marketId);
    }

    /**
     * @notice Allows users to withdraw winnings from multiple markets
     * @param marketIds Array of market IDs to withdraw from
     */
    function withdraw(uint[] memory marketIds) external {
        for (uint i; i < marketIds.length; ++i) {
            _withdraw(marketIds[i]);
        }
    }

    /**
     * @notice Allows users to recover their funds
     */
    function recoveryUserFunds() external {
        IERC20(USDC_BASE_SEPOLIA).transfer(msg.sender, userVolume[msg.sender]);
    }

    //║══════════════════════════════════════════╗
    //║    Pub View  Functions                   ║
    //║══════════════════════════════════════════╝

    /**
     * @notice Calculates the cost of buying shares
     * @param marketId ID of the target market
     * @param optionId ID of the option to buy
     * @param quantity Number of shares to buy
     * @return totalCost Total cost for the purchase
     */
    function calculateBuyCost(uint256 marketId, uint256 optionId, uint256 quantity) public view returns (uint256 totalCost) {
        Market storage market = markets[marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "Quantity must be greater than zero");

        uint256 currentShares = market.options[optionId].shares;
        
        // Special case for when there are no shares - return initial price * quantity
        if (currentShares == 0) {
            return market.options[optionId].initialPrice * quantity;
        }

        uint256 runningCost = 0;
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 sumExp = 0;
            for (uint256 j = 0; j < market.options.length; j++) {
                Option storage option = market.options[j];
                uint256 shares = option.shares;
                if (j == optionId) {
                    shares = currentShares + i;
                }
                uint256 currImpact = calculateImpact(
                    shares,
                    BASE_IMPACT_FACTOR,
                    market.impactPower
                );
                uint256 currWeight = option.initialPrice + currImpact;
                sumExp += currWeight;
            }

            uint256 impact = calculateImpact(
                currentShares + i,
                BASE_IMPACT_FACTOR,
                market.impactPower
            );
            uint256 weight = market.options[optionId].initialPrice + impact;
            uint256 price = (weight * TOTAL_PRICE) / sumExp;
            
            runningCost += price;
        }

        return runningCost;
    }

    /**
     * @notice Calculates the return from selling shares
     * @param marketId ID of the target market
     * @param optionId ID of the option to sell
     * @param quantity Number of shares to sell
     * @return totalReturn Total return from the sale
     */
    function calculateSellReturn(uint256 marketId, uint256 optionId, uint256 quantity) public view returns (uint256 totalReturn) {
        require(marketId < marketCount, "Invalid market ID");
        Market storage market = markets[marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "Quantity must be greater than zero");

        Option storage option = market.options[optionId];
        uint256 currentShares = option.shares;
        require(currentShares >= quantity, "Not enough shares to sell");

        uint256 sumExp = 0;
        for (uint256 i = 0; i < market.options.length; i++) {
            uint256 shares = market.options[i].shares;
            uint256 currImpact = calculateImpact(shares, BASE_IMPACT_FACTOR, market.impactPower);
            uint256 currWeight = market.options[i].initialPrice + currImpact;
            sumExp += currWeight;
        }

        uint256 impact = calculateImpact(currentShares, BASE_IMPACT_FACTOR, market.impactPower);
        uint256 weight = option.initialPrice + impact;
    
        if (quantity == 1) {
            return option.initialPrice;
        } else {
            impact = calculateImpact(currentShares - quantity, BASE_IMPACT_FACTOR, market.impactPower);
            weight = option.initialPrice + impact;
            uint256 adjustedSellPrice = (weight * TOTAL_PRICE) / sumExp;
            return quantity * adjustedSellPrice;
        }
    }

    /**
     * @notice Gets market information
     * @param marketId ID of the market
     * @return prices Array of current prices for each option
     * @return optionsNames Array of marketId option names
     * @return total Total of all prices
     */
    function getMarketInfo(uint256 marketId) public view returns (
        uint256[] memory prices, 
        string[] memory optionsNames,
        uint256 total
    ) {
        Market storage market = markets[marketId];
        prices = new uint256[](market.options.length);
        optionsNames = new string[](market.options.length);
        total = 0;

        for (uint256 i = 0; i < market.options.length; i++) {
            prices[i] = market.options[i].price;
            total += prices[i];
            optionsNames[i] = market.options[i].optionName;
        }
        
    }

    /**
     * @notice Gets the number of options in a market
     * @param marketId ID of the market
     * @return Number of options
     */
    function getMarketOptionCount(uint256 marketId) public view returns (uint256) {
        return markets[marketId].options.length;
    }

    /**
     * @notice Gets user's shares in a specific market
     * @param user Address of the user
     * @param marketId ID of the market
     * @return userShares Array of user's shares for each option
     */
    function getUserSharesPerMarket(address user, uint marketId) public view returns (uint[] memory userShares) {
        userShares = userMarketShares[user][marketId].shares;
    }

    //║══════════════════════════════════════════╗
    //║    Internal  Functions                   ║
    //║══════════════════════════════════════════╝

    /**
     * @notice Calculates price impact using power law
     * @dev Uses simplified power approximation for demonstration
     * @param shares Number of shares
     * @param baseImpact Base impact factor
     * @param power Power factor
     * @return Calculated impact value
     */
    function calculateImpact(uint256 shares, uint256 baseImpact, uint256 power) internal pure returns (uint256) {
        if (shares == 0) return 0;
        if (shares == 1) return baseImpact;
        
        uint256 scaledShares = shares * IMPACT_POWER_SCALE;
        uint256 powResult = 0;
        
     
        if (power == IMPACT_POWER_SCALE) { // power = 1.0
            powResult = scaledShares;
        } else if (power == IMPACT_POWER_SCALE * 2) { // power = 2.0
            powResult = (shares * shares) * IMPACT_POWER_SCALE;
        } 
        
        return (baseImpact * powResult) / IMPACT_POWER_SCALE;
    }

    /**
     * @notice Updates market prices based on current shares distribution
     * @dev Implements LMSR (Logarithmic Market Scoring Rule) pricing mechanism
     * @param marketId ID of the market to update
     */
    function _updateMarketPrices(uint256 marketId) internal {
        Market storage market = markets[marketId];
        uint256 optionCount = market.options.length;
        
        uint256 sumExp = 0;
        for (uint256 i = 0; i < optionCount; i++) {
            Option storage option = market.options[i];
            uint256 impact = calculateImpact(
                option.shares, 
                BASE_IMPACT_FACTOR,
                market.impactPower
            );
            uint256 weight = option.initialPrice + impact;
            sumExp += weight;
        }

        if (sumExp > 0) {
            for (uint256 i = 0; i < optionCount; i++) {
                Option storage option = market.options[i];
                uint256 impact = calculateImpact(
                    option.shares, 
                    BASE_IMPACT_FACTOR,
                    market.impactPower
                );
                uint256 weight = option.initialPrice + impact;
                option.price = (weight * TOTAL_PRICE) / sumExp;
            }
        }
    }

    /**
     * @notice Internal function to process user withdrawals from a resolved market
     * @dev Calculates and transfers rewards based on winning shares
     * @param marketId ID of the market to withdraw from
     */
    function _withdraw(uint marketId) internal {
        Market memory market = markets[marketId];
        UserShares memory userShares = userMarketShares[msg.sender][marketId];
        require(!userShares.claimed, "Already claimed");
        uint totalWinningShares = market.options[market.winningOptionIndex].shares;
        uint rewardPerShare = market.prizePool / totalWinningShares;
        uint userRewards = rewardPerShare * userShares.shares[market.winningOptionIndex];
        
        IERC20(USDC_BASE_SEPOLIA).transfer(msg.sender, userRewards);
    }   
}