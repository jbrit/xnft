// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../src/XNFT.sol";
import "../src/HubNFTWrapper.sol";
import "../src/SpokeNFT.sol";

contract WrapperScript is Script {
    mapping(uint16 => uint256) chainToForkId;

    mapping(uint16 => string) supportedChain;
    mapping(uint16 => address) relayers;

    address nftWrapper;
    mapping(uint16 => address) spokes;

    modifier onlySupportedChain(uint16 chainId){
      require(bytes(supportedChain[chainId]).length > 0, "Unsupported chain");
      _;
   }

    function setUp() public {
        supportedChain[10002] = "sepolia";
        supportedChain[10003] = "arbitrum_sepolia";
        supportedChain[10004] = "base_sepolia";
        relayers[10002] = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        relayers[10003] = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        relayers[10004] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
    }

    function switchToChainId(uint16 chainId) public onlySupportedChain(chainId){
        if(chainToForkId[chainId] == 0){
            chainToForkId[chainId] = vm.createSelectFork(vm.rpcUrl(supportedChain[chainId]));
        } else {
            vm.selectFork(chainToForkId[chainId]);
        }
    }
    function deployNFTAndWrap(uint16 _chainId) public returns (address){
        vm.startBroadcast();
        XNFT xnft = new XNFT();
        vm.stopBroadcast();
        return deployWrapper(address(xnft), _chainId);
    }

    function deployWrapper(address _tokenAddress, uint16 _chainId) public returns (address) {
        vm.startBroadcast();
        HubNFTWrapper hnw = new HubNFTWrapper(_tokenAddress, relayers[_chainId], _chainId);
        nftWrapper = address(hnw);
        vm.stopBroadcast();
        return address(hnw);
    }

    function deploySpoke(string memory name, string memory symbol, uint16 _chainId) public returns (address) {
        SpokeNFT nsn = new SpokeNFT(name, symbol, _chainId);
        spokes[_chainId] = address(nsn);
        return address(nsn);
    }

    function run() public {
        uint256 i;
        uint256 j; // for loops

        uint16 baseChainId = 10002; // arg
        require(bytes(supportedChain[baseChainId]).length > 0, "Unsupported Base chain");
        switchToChainId(baseChainId);

        vm.startBroadcast();
        XNFT xnft = new XNFT();
        vm.stopBroadcast();

        string memory name = xnft.name(); // arg
        string memory symbol = xnft.symbol(); // arg
        

        // IERC721 baseNFT = IERC721(xnft); // arg


        uint16[2] memory otherChains = [10003, 10004]; // arg
        for (i = 0; i < otherChains.length; i++){
            // validate other chains first
            require(bytes(supportedChain[otherChains[i]]).length > 0, string.concat("Unsupported chain: ", vm.toString(otherChains[i])));
        }

        // step 1 - deploy wrapper
        vm.startBroadcast();
        deployWrapper(address(xnft), baseChainId);
        vm.stopBroadcast();

        // step 2 - deploy spokes
        for (i = 0; i < otherChains.length; i++){
            uint16 chainId = otherChains[i];
            switchToChainId(chainId);
            vm.startBroadcast();
            deploySpoke(name, symbol, chainId);
            vm.stopBroadcast();
        }

        // switchToChainId(baseChainId);
        // register spokes on hub
        //  for (i = 0; i < otherChains.length; i++){
        //     uint16 chainId = otherChains[i];
        //     vm.startBroadcast();
        //     nftWrapper.setRegisteredPeer(chainId, spokes[chainId]);
        //     vm.stopBroadcast();                       
        //  }

        //  register hub & spoke on spokes
        //  for (i = 0; i < otherChains.length; i++){
        //     uint16 chainId = otherChains[i]; // registering on this chain
        //     switchToChainId(chainId);
        //     SpokeNFT spoke = SpokeNFT(spokes[chainId]);
        //     vm.startBroadcast();
        //     for (j = 0; j < otherChains.length; j++){
        //         if (j == 0) { // do hub registration on first iteration
        //             spoke.setRegisteredPeer(baseChainId, address(nftWrapper));
        //         }
        //         if (i != j) {
        //             spoke.setRegisteredPeer(chainId, spokes[chainId]);
        //         }
        //     }                     
        //     vm.stopBroadcast();
        //  }
        
    }
}
