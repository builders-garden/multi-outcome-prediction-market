// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0 ^0.8.20;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/interface/IMultiOutcomePredictionMarket.sol

interface IMultiOutcomePredictionMarket {
    
    event MarketCreated(uint indexed marketId, string[] optionNames);
    event MarketResolved(uint indexed marketId, uint winningOptionIndex, string winningOptionName);
    event BoughtShares(address indexed user, uint indexed marketId, uint optionId, uint amount, uint totalCost);
    event SoldShares(address indexed user, uint indexed marketId, uint optionId, uint amount, uint totalReturn);
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

// src/MultiOutcomePredictionMarket.sol

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
     */
    function createMarket(
        uint256[] memory initialPrices, 
        string[] memory optionNames
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

        for (uint256 i = 0; i < initialPrices.length; i++) {
            newMarket.options.push(Option(0, initialPrices[i], initialPrices[i], optionNames[i]));
            
        }   

        emit MarketCreated(marketCount, optionNames);
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
        require(!market.resolved, "This market already resolved");
        require(marketId <= marketCount, "Market dosen't exists");
        require(winningOptionIndex < market.options.length , "Option out of array bounds");
        market.winningOptionIndex = winningOptionIndex;
        market.resolved = true;

        emit MarketResolved(
            marketId,
            winningOptionIndex, 
            markets[marketId].options[winningOptionIndex].optionName
        );
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
        require(!isEmergencyState, "Contract is paused");
        require(!market.resolved, "Market is resolved");
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "quantity must be greater than zero");
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

        emit BoughtShares(msg.sender, marketId, optionId, quantity, cost);
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
        require(!isEmergencyState, "Contract is paused");
        require(!market.resolved, "Market is resolved");
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "quantity must be greater than zero");
        require(userShares.shares[optionId] >= quantity, "Not enough shares to sell");
        require(marketId <= marketCount, "Market dosen't exists");
        
        
        uint sellReturn = calculateSellReturn(marketId, optionId, quantity);
        market.options[optionId].shares -= quantity;
        userShares.shares[optionId] -= quantity;

        userVolume[msg.sender] -= sellReturn;
        market.prizePool -= sellReturn;

        IERC20(USDC_BASE_SEPOLIA).transfer(msg.sender, sellReturn);

        _updateMarketPrices(marketId);

        emit SoldShares(msg.sender, marketId, optionId, quantity, sellReturn);
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
    

    /* @notice Calculates the cost of buying shares with exact price matching
    * @param marketId ID of the target market
    * @param optionId ID of the option to buy
    * @param quantity Number of shares to buy
    * @return totalCost Total cost for the purchase
    */
    function calculateBuyCost(
        uint256 marketId,
        uint256 optionId,
        uint256 quantity
    ) public view returns (uint256 totalCost) {
        Market storage market = markets[marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "Quantity must be greater than zero");

        // If buying 1 share, return current price
        if (quantity == 1) {
            return market.options[optionId].price;
        }

        uint256 currentShares = market.options[optionId].shares;
        uint256 firstShareCost = market.options[optionId].price;
        
        // Calculate second share cost after theoretical first purchase
        uint256 sumExp = 0;
        for (uint256 i = 0; i < market.options.length; i++) {
            uint256 shares = market.options[i].shares;
            if (i == optionId) {
                shares += 1; // Add the theoretical first share
            }
            uint256 currImpact = calculateImpact(shares);
            uint256 currWeight = market.options[i].initialPrice + currImpact;
            sumExp += currWeight;
        }

        // Calculate price for second share
        uint256 impact = calculateImpact(currentShares + 1);
        uint256 weight = market.options[optionId].initialPrice + impact;
        uint256 secondSharePrice = (weight * TOTAL_PRICE) / sumExp;

        // Calculate total cost using arithmetic progression for all quantities > 1
        uint256 priceIncrement = secondSharePrice - firstShareCost;
        uint256 remainingShares = quantity - 1;
        uint256 lastSharePrice = firstShareCost + (priceIncrement * remainingShares);
        
        // First share + arithmetic mean of remaining shares prices * number of remaining shares
        return firstShareCost + (remainingShares * (secondSharePrice + lastSharePrice) / 2);
    }

    function calculateSellReturn(
        uint256 marketId,
        uint256 optionId,
        uint256 quantity
    ) public view returns (uint256 totalReturn) {
        Market storage market = markets[marketId];
        require(optionId < market.options.length, "Invalid option ID");
        require(quantity > 0, "Quantity must be greater than zero");

        Option storage option = market.options[optionId];
        uint256 currentShares = option.shares;
        require(currentShares >= quantity, "Not enough shares to sell");
        
        // Calculate first share return
        uint256 sumExp = 0;
        for (uint256 i = 0; i < market.options.length; i++) {
            uint256 shares = market.options[i].shares;
            if (i == optionId) {
                shares -= 1; // Consider one share already sold
            }
            uint256 currImpact = calculateImpact(shares);
            uint256 currWeight = market.options[i].initialPrice + currImpact;
            sumExp += currWeight;
        }

        uint256 impact = calculateImpact(currentShares - 1);
        uint256 weight = option.initialPrice + impact;
        uint256 firstShareReturn = (weight * TOTAL_PRICE) / sumExp;

        // If selling 1 share, return the calculated price
        if (quantity == 1) {
            return firstShareReturn;
        }

        // Calculate last share price
        sumExp = 0;
        for (uint256 i = 0; i < market.options.length; i++) {
            uint256 shares = market.options[i].shares;
            if (i == optionId) {
                shares -= quantity; // Consider all shares being sold
            }
            uint256 currImpact = calculateImpact(shares);
            uint256 currWeight = market.options[i].initialPrice + currImpact;
            sumExp += currWeight;
        }
        
        impact = calculateImpact(currentShares - quantity);
        weight = option.initialPrice + impact;
        uint256 lastShareReturn = (weight * TOTAL_PRICE) / sumExp;

        // Calculate total return using arithmetic mean
        uint256 remainingShares = quantity - 1;
        return firstShareReturn + (remainingShares * (firstShareReturn + lastShareReturn) / 2);
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
     * @notice Gets market winning option
     * @param marketId ID of the market
     * @return winningOption Index of the winning option
     * @return winningOptionName Name of the winning option
     */
    function getMarketWinner(uint marketId) public view returns (uint winningOption, string memory winningOptionName){
        winningOption = markets[marketId].winningOptionIndex;
        winningOptionName = markets[marketId].options[winningOption].optionName;
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
     * @return Calculated impact value
     */
    function calculateImpact(uint256 shares) internal pure returns (uint256) {
        if (shares == 0) return 0;
        if (shares == 1) return BASE_IMPACT_FACTOR;
        
        uint256 scaledShares = shares * IMPACT_POWER_SCALE;    
        return (BASE_IMPACT_FACTOR * scaledShares) / IMPACT_POWER_SCALE;
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
                option.shares
            );
            uint256 weight = option.initialPrice + impact;
            sumExp += weight;
        }

        if (sumExp > 0) {
            for (uint256 i = 0; i < optionCount; i++) {
                Option storage option = market.options[i];
                uint256 impact = calculateImpact(
                    option.shares
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
        uint userWinningShares = userShares.shares[market.winningOptionIndex];
        uint totalWinningShares = market.options[market.winningOptionIndex].shares;
        uint rewardPerShare = market.prizePool / totalWinningShares;
        uint userRewards = rewardPerShare * userWinningShares;
        
        IERC20(USDC_BASE_SEPOLIA).transfer(msg.sender, userRewards);

        emit Withdrawal(msg.sender, marketId, userWinningShares, userRewards);
    }   
}
