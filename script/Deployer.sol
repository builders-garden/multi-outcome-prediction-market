// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MultiOutcomePredictionMarket} from "../src/MultiOutcomePredictionMarket.sol";


contract MultiOutcomePredictionMarketDeployer is Script {
    MultiOutcomePredictionMarket public predictionMarket;
    address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    uint[]  optionPrices = new uint[](0);
    string[]  optionNames = new string[](0);
    function setUp() public {
    }

    function run() public {
        uint options;
    //║════════════════════════════════╗
    //║            Market 1            ║
    //║════════════════════════════════╝
        options = 8;
        for (uint i = 0; i < options; i++) {
            optionPrices.push(125000);
        }
 
        optionNames.push("Orbulo");
        optionNames.push("Limone");
        optionNames.push("Frank");
        optionNames.push("Bianc8");
        optionNames.push("Drone");
        optionNames.push("Fraye");
        optionNames.push("Caso");
        optionNames.push("Blackicon");

        delete optionNames;
        delete optionPrices;

    //║════════════════════════════════╗
    //║            Market 2            ║
    //║════════════════════════════════╝

        options = 5;
        for (uint i = 0; i < options; i++) {
            optionPrices.push(125000);
        }
        
        optionNames.push("Orbulo");
        optionNames.push("Limone");
        optionNames.push("Frank");
        optionNames.push("Bianc8");
        optionNames.push("Drone");

        delete optionNames;
        delete optionPrices;

    //║════════════════════════════════╗
    //║            Market 1            ║
    //║════════════════════════════════╝

    }
}
