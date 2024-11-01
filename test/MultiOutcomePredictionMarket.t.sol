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
        // Init a market with 125_000 * 8
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
        // Init a market with 125_000 * 8
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
        uint optionsCount = 12;
        createMarketWithDynamicOptions(optionsCount);
        // this test is just to check prices are moving consistently, dosen't take into account
        // other actors in the process
        // buy 100 shares of option 0
        consoleLogMarketInfos(1, "before anything");
        uint256 costOf100Shares;
        uint dealt;
        
        for (uint i; i < optionsCount; i++){
            costOf100Shares =  predictionMarket.calculateBuyCost(1, i, 100);
            deal(address(usdc), address(this), costOf100Shares);
            dealt += costOf100Shares;
            usdc.approve(address(predictionMarket), costOf100Shares);
            predictionMarket.buy(1, i, 100);
            consoleLogMarketInfos(1, string(abi.encodePacked("after buying 100 shares of ", uint2str(i))));
        } 
       
        uint256 returnOf100Shares;
        uint earned;

        for (uint i; i < optionsCount; i++){
            uint preBal = usdc.balanceOf(address(this));
            returnOf100Shares = predictionMarket.calculateSellReturn(1, i, 100);
            
            predictionMarket.sell(1,i, 100);
            uint afterBal = usdc.balanceOf(address(this));
            earned += afterBal - preBal;
            consoleLogMarketInfos(1, string(abi.encodePacked("after selling 100 shares of ", uint2str(i))));
        } 

        //║══════════════════════════════════════════╗
        //║    Balance asserts                       ║
        //║══════════════════════════════════════════╝


        uint256 actualBalance = usdc.balanceOf(address(this));
        uint256 expectedBalance = dealt;

        // Calculate 1% of the expected balance
        uint256 tolerance = expectedBalance * 1 / 1000;

        // Check if the actual balance is within the 1% tolerance range of the expected balance
        require(
            actualBalance >= expectedBalance - tolerance && actualBalance <= expectedBalance + tolerance,
            string(abi.encodePacked("Expected: ", uint2str(expectedBalance), " but got: ", uint2str(actualBalance)))
        );
        // check if earnings are in range of 1% tolerance against dealt usdc 
        require(
            earned >= expectedBalance - tolerance && earned <= expectedBalance + tolerance,
            string(abi.encodePacked("Expected: ", uint2str(expectedBalance), " but got: ", uint2str(actualBalance)))
        );
    }

    function testBuyingAndSellingBackLeavesWithStartingBalance(uint8 numOptions, uint64 shareAmount) public {
        // Ensure numOptions is within the specified range
        vm.assume((numOptions >= 4 && numOptions <= 12) && shareAmount >= 1 && shareAmount <= 1e4);
        uint amount = uint(shareAmount);
        createMarketWithDynamicOptions(uint(numOptions));
         // this test is just to check prices are moving consistently, dosen't take into account
        // other actors in the process
        // buy 100 shares of option 0
        consoleLogMarketInfos(1, "before anything");
        uint256 costOf100Shares;
        uint dealt;
        
        for (uint i; i < numOptions; i++){
            costOf100Shares =  predictionMarket.calculateBuyCost(1, i, 100);
            deal(address(usdc), address(this), costOf100Shares);
            dealt += costOf100Shares;
            usdc.approve(address(predictionMarket), costOf100Shares);
            predictionMarket.buy(1, i, 100);
            consoleLogMarketInfos(1, string(abi.encodePacked("after buying 100 shares of ", uint2str(i))));
        } 
       
        uint256 returnOf100Shares;
        uint earned;

        for (uint i; i < numOptions; i++){
            uint preBal = usdc.balanceOf(address(this));
            returnOf100Shares = predictionMarket.calculateSellReturn(1, i, 100);
            
            predictionMarket.sell(1,i, 100);
            uint afterBal = usdc.balanceOf(address(this));
            earned += afterBal - preBal;
            consoleLogMarketInfos(1, string(abi.encodePacked("after selling 100 shares of ", uint2str(i))));
        } 

        //║══════════════════════════════════════════╗
        //║    Balance asserts                       ║
        //║══════════════════════════════════════════╝


        uint256 actualBalance = usdc.balanceOf(address(this));
        uint256 expectedBalance = dealt;

        // Calculate 1% of the expected balance
        uint256 tolerance = expectedBalance * 1 / 1000;

        // Check if the actual balance is within the 1% tolerance range of the expected balance
        require(
            actualBalance >= expectedBalance - tolerance && actualBalance <= expectedBalance + tolerance,
            string(abi.encodePacked("Expected: ", uint2str(expectedBalance), " but got: ", uint2str(actualBalance)))
        );
        // check if earnings are in range of 1% tolerance against dealt usdc 
        require(
            earned >= expectedBalance - tolerance && earned <= expectedBalance + tolerance,
            string(abi.encodePacked("Expected: ", uint2str(expectedBalance), " but got: ", uint2str(actualBalance)))
        );
    }




    function consoleLogMarketInfos(uint marketId, string memory text) internal {
        (uint[] memory marketPrices, , ) =  predictionMarket.getMarketInfo(marketId);
                console.log("[-----------", text ,"----------]");
                for (uint i = 0; i < marketPrices.length; i++) {
            console.log("currPrice of id:", i, "is", marketPrices[i]);
        }
    }


    function testOptionMarketResolutoin() public {
        // Init a market with 125_000 * 8
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
            // Init a market with 125_000 * 8
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

        

        predictionMarket.createMarket(initialOptionPrices, optionNames);
    }


    function createMarketWithDynamicOptions(uint256 numberOfOptions) internal {
        require(numberOfOptions > 0, "Number of options must be greater than zero");
        
        uint[] memory initialOptionPrices = new uint[](numberOfOptions);
        uint256 totalPrice = 1e6; // Total sum of option prices
        uint256 basePrice = totalPrice / numberOfOptions; // Base price for each option
        uint256 remainder = totalPrice % numberOfOptions; // Handle any remainder

        // Distribute prices evenly and handle the remainder
        for (uint256 i = 0; i < numberOfOptions; i++) {
            initialOptionPrices[i] = basePrice + (i < remainder ? 1 : 0);
        }

        // Create an array of empty strings for option names
        string[] memory optionNames = new string[](numberOfOptions);
        for (uint256 i = 0; i < numberOfOptions; i++) {
            optionNames[i] = ""; // Fill with empty strings
        }

        bool isQuadratic = true;

        predictionMarket.createMarket(initialOptionPrices, optionNames);
    }


    function singleMarketCreationAnd1SharesAcquired() internal {
        // Init a market with 125_000 * 8
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


    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        return string(bstr);
    }

}
