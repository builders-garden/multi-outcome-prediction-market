// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MultiOutcomePredictionMarket} from "../src/MultiOutcomePredictionMarket.sol";
import "./mockUSDC.sol";

contract MultiOutcomePredictionMarketTest is Test {
    MultiOutcomePredictionMarket public predictionMarket;
    MockUsdc usdc; 
    function setUp() public {
        usdc = new MockUsdc();
        predictionMarket = new MultiOutcomePredictionMarket(address(this), address(usdc));
    }

    function testMarketCreation() public {

        uint[] memory initialOptionPrices = new uint[](8);
        for (uint i = 0; i < initialOptionPrices.length; i++) {
            initialOptionPrices[i] = 125000;
        }

        string[] memory optionNames = new string[](8);
        optionNames[0] = "Orbulo";
        optionNames[1] = "Limone";
        optionNames[2] = "Frank";
        optionNames[3] = "Bianc8";
        optionNames[4] = "Drone";
        optionNames[5] = "Fraye";
        optionNames[6] = "Caso";
        optionNames[7] = "Blackicon";

        bool isQuadratic = true;

        predictionMarket.createMarket(initialOptionPrices, optionNames);
        
        assertEq(predictionMarket.getMarketOptionCount(1), initialOptionPrices.length);
        assertEq(predictionMarket.marketCount(), 1);

        (
            uint256[] memory prices, 
            string[] memory registredOptionNames,
            uint256 total
        ) = predictionMarket.getMarketInfo(1);

        assertEq(initialOptionPrices, prices);
        assertEq(optionNames, registredOptionNames);
        assertEq(total, 1e6);
        
        // Expect a revert when sum of the options isnt precisely 1e6
        initialOptionPrices[0] = 125000 + 1;
        vm.expectRevert();
        predictionMarket.createMarket(initialOptionPrices, optionNames);
        
        // Expect revert with length 0 array
        uint[] memory emptyPricesArray;
        string[] memory emptyNameArray;
        vm.expectRevert();
        predictionMarket.createMarket(emptyPricesArray, emptyNameArray);
        
        // Expect revert when prices and names length don't match
        vm.expectRevert();
        predictionMarket.createMarket(emptyPricesArray, optionNames);

        // Expect revert if the msg.sender isn't admin
        vm.prank(address(1));
        vm.expectRevert();
        predictionMarket.createMarket(initialOptionPrices, optionNames);
        
    }  
    
    function testBuyOptions() public{
        // create market 1
        singleMarketCreation();
        uint256 costOfNextShare = predictionMarket.calculateBuyCost(1, 0, 1);
        // cost of the first share should be equal to initial price (125000);
        assertEq(costOfNextShare, 125000);
        
        deal(address(usdc), address(this), costOfNextShare);
        usdc.approve(address(predictionMarket), costOfNextShare);
        
        // Log the actual approval
        uint256 actualApproval = usdc.allowance(address(this), address(predictionMarket));
        // buy from market 1, option 0, quantity 1
        predictionMarket.buy(1, 0, 1);
        
        // assert user owns one share of option 0
        assertEq(predictionMarket.getUserSharesPerMarket(address(this), 1)[0], 1);

        // calculate next 10 shares cost and deal
        uint costOfNext10Shares = predictionMarket.calculateBuyCost(1, 0, 10);
        deal(address(usdc), address(this), costOfNext10Shares);
        usdc.approve(address(predictionMarket), costOfNext10Shares);

        // expect revert if market dosen't exist
        vm.expectRevert();
        predictionMarket.buy(2, 0, 1);

        // expect revert if quantity is zero
        vm.expectRevert();
        predictionMarket.buy(1, 0, 0);

        // exect revert if option is out of bound
        vm.expectRevert();
        predictionMarket.buy(1, 10, 1);

        // test cost simulation is working properly when buying multiple shares
        predictionMarket.buy(1, 0, 10);

        // assert user owns 1 + 10 shares of option 0
        assertEq(predictionMarket.getUserSharesPerMarket(address(this), 1)[0], 11);
    }

    function testSellOptions() public {
        singleMarketCreation();

        // Buy option 1 
        uint256 costOfNextShare = predictionMarket.calculateBuyCost(1, 0, 1);
        // cost of the first share should be equal to initial price (125000);
        assertEq(costOfNextShare, 125000);
        
        deal(address(usdc), address(this), costOfNextShare);
        usdc.approve(address(predictionMarket), costOfNextShare);
        
        // Log the actual approval
        uint256 actualApproval = usdc.allowance(address(this), address(predictionMarket));
        // buy from market 1, option 0, quantity 1
        predictionMarket.buy(1, 0, 1);
        
        assertEq(predictionMarket.getUserSharesPerMarket(address(this), 1)[0], 1);
        uint256 rewardForNextShare = predictionMarket.calculateSellReturn(1, 0, 1);
        
        predictionMarket.sell(1 ,0 ,1);
        // Buying and selling right after should turn the price at its initial state
        assertEq(rewardForNextShare, 125000);
        // Assert that user has 0 shares of option 0 after selling
        assertEq(predictionMarket.getUserSharesPerMarket(address(this), 1)[0], 0);
        // expect revert when selling shares you don't own
        vm.expectRevert();
        predictionMarket.sell(1,0,1);
    }

    function testBuyingAndSellingBackLeavesWithStartingBalance() public {
        singleMarketCreation();

        // this test is just to check prices are moving consistently, dosen't take into account
        // other actors in the process

        // buy 100 shares of option 0
        
        uint256 costOf100Shares = predictionMarket.calculateBuyCost(1, 0, 100);
        console.log("Buy 100 for: ", costOf100Shares);
        deal(address(usdc), address(this), costOf100Shares);
        usdc.approve(address(predictionMarket), costOf100Shares);
        predictionMarket.buy(1, 0, 100);
        // sell 100 shares of option 0 
        

        uint256 returnOf100Shares = predictionMarket.calculateSellReturn(1, 0, 100);
        console.log("Sell 100 for: ",returnOf100Shares);
        predictionMarket.sell(1,0, 100);
        
        // assert balance is unchanged after that
        assertEq(costOf100Shares, usdc.balanceOf(address(this)));
    }

    function testOptionMarketResolutoin() public {
        singleMarketCreation();
        
        // only admin shall call this function
        vm.prank(address(1));
        vm.expectRevert();
        predictionMarket.optimisticMarketResolution(1, 1);

        // expect revert when resolving non existent market
        vm.expectRevert();
        // resolve unexisting market 10 with option index 1 as winner;
        predictionMarket.optimisticMarketResolution(10, 1);

        // expect revert when resolving non existent option
        vm.expectRevert();
        // resolve marketId 1 with unexisting option as winner; 
        predictionMarket.optimisticMarketResolution(1, 20);


        // resolve marketId 1 with option index 1 as winner;
        predictionMarket.optimisticMarketResolution(1, 1);
        // assert winning index for market 1 is indeed option index 1
        (uint winningIndex, )= predictionMarket.getMarketWinner(1);
        assertEq(winningIndex, 1);


        // expect revert if resolution already happened 
        // resolve marketId 1 with option index 1 as winner;
        vm.expectRevert();
        predictionMarket.optimisticMarketResolution(1, 1);
    }

    function testBatchOptionMarketResolution() public {
        // create 10 markets
        for(uint i; i < 8; ++i){
            singleMarketCreation();
        }
        
        // create arrays for batching so that market 0 wins 0, market 1 wins 1 [..]
        uint[] memory marketIds = new uint[](8);
        uint[] memory winningIndexes = new uint[](8);
        for (uint i; i < marketIds.length; i++) {
            marketIds[i] = i + 1; // market ids start from 1, so we add +1
            winningIndexes[i] = i;
        }  

        predictionMarket.batchOptimisticMarketResolution(marketIds, winningIndexes);

    }

    function testDeclareEmergency() public {
        singleMarketCreationAnd1SharesAcquired();

        // set emergency state
        predictionMarket.declareEmergency(true);

        // expect revert on selling when emergency state is activated;
        vm.expectRevert();
        predictionMarket.sell(1,0,1);
        

        // same for buying 

        uint256 costOfNextShare = predictionMarket.calculateBuyCost(1, 0, 1);
        deal(address(usdc), address(this), costOfNextShare);
        usdc.approve(address(predictionMarket), costOfNextShare);
        uint256 actualApproval = usdc.allowance(address(this), address(predictionMarket));
  
        vm.expectRevert();
        predictionMarket.buy(1, 0, 1);

        
        // set emergency state to false
        predictionMarket.declareEmergency(false);
        // sell should go trough now
        predictionMarket.sell(1,0,1);
    }

    function singleMarketCreation() internal {
        uint[] memory initialOptionPrices = new uint[](8);
        for (uint i = 0; i < initialOptionPrices.length; i++) {
            initialOptionPrices[i] = 125000;
        }

        string[] memory optionNames = new string[](8);
        optionNames[0] = "Orbulo";
        optionNames[1] = "Limone";
        optionNames[2] = "Frank";
        optionNames[3] = "Bianc8";
        optionNames[4] = "Drone";
        optionNames[5] = "Fraye";
        optionNames[6] = "Caso";
        optionNames[7] = "Blackicon";

        bool isQuadratic = true;

        predictionMarket.createMarket(initialOptionPrices, optionNames);
    }

    function singleMarketCreationAnd1SharesAcquired() internal {
        singleMarketCreation();
        uint256 costOfNextShare = predictionMarket.calculateBuyCost(1, 0, 1);
        // cost of the first share should be equal to initial price (125000);
        assertEq(costOfNextShare, 125000);
        
        deal(address(usdc), address(this), costOfNextShare);
        usdc.approve(address(predictionMarket), costOfNextShare);
        
        // Log the actual approval
        uint256 actualApproval = usdc.allowance(address(this), address(predictionMarket));
        // buy from market 1, option 0, quantity 1
        predictionMarket.buy(1, 0, 1);
    }

}
