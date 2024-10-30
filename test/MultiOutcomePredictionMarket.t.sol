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

        predictionMarket.createMarket(initialOptionPrices, optionNames, isQuadratic);
        
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
        predictionMarket.createMarket(initialOptionPrices, optionNames, isQuadratic);
        
        // Expect revert with length 0 array
        uint[] memory emptyPricesArray;
        string[] memory emptyNameArray;
        vm.expectRevert();
        predictionMarket.createMarket(emptyPricesArray, emptyNameArray, isQuadratic);
        
        // Expect revert when prices and names length don't match
        vm.expectRevert();
        predictionMarket.createMarket(emptyPricesArray, optionNames, isQuadratic);

        // Expect revert if the msg.sender isn't admin
        vm.prank(address(1));
        vm.expectRevert();
        predictionMarket.createMarket(initialOptionPrices, optionNames, isQuadratic);
        
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

        uint256 rewardForNextShare = predictionMarket.calculateSellReturn(1, 0, 1);
        
        predictionMarket.sell(1,0,1);
        assertEq(rewardForNextShare, 125000);

    }

    function testOptionMarketResolutoin() public {
        singleMarketCreation();
    }

    function testBatchOptionMarketResolution() public {
        singleMarketCreation();
    }

    function testDeclareEmergency() public {

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

        predictionMarket.createMarket(initialOptionPrices, optionNames, isQuadratic);
    }
}
