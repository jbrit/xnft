// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {HubNFTWrapper} from "../src/HubNFTWrapper.sol";
import {SpokeNFT} from "../src/SpokeNFT.sol";

contract CounterTest is Test {
    HubNFTWrapper public nftWrapper;
    SpokeNFT public spokeNFT;

    function setUp() public {
        spokeNFT = new SpokeNFT();
        nftWrapper = new HubNFTWrapper(address(spokeNFT));
    }

    function test_works() public{
        address alice = address(2);
        vm.startPrank(alice);
        spokeNFT.mint(alice, 0);
        spokeNFT.safeTransferFrom(alice, address(nftWrapper), 0, abi.encode(0, alice));
        vm.stopPrank();
    }
}
