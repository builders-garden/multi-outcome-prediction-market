// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MultiOutcomePredictionMarket} from "../src/MultiOutcomePredictionMarket.sol";


contract ResolverScript is Script {

    MultiOutcomePredictionMarket public predictionMarket;
    address predictionMarketAddress = (address(0));


    function setUp() public {
        predictionMarket = MultiOutcomePredictionMarket(predictionMarketAddress);
    }

    function run() public {
        uint[] memory marketIds = new uint[](8);
        uint[] memory winningIndexes = new uint[](8);
        // market 1, winner option 2
        marketIds[0] = 1;
        winningIndexes[0] = 2;

        predictionMarket.batchOptimisticMarketResolution(marketIds, winningIndexes);
    }
}
