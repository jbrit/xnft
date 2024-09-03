// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeReceiver.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract SpokeNFT is ERC721, IWormholeReceiver, Ownable {
    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable chainId;
    uint256 constant GAS_LIMIT = 100_000;

    mapping(bytes32 deliveryHash => bool) private _usedHash;
    mapping(uint16 => address) registeredPeers;

    constructor(string memory name, string memory symbol, uint16 _chainId) ERC721(name, symbol) Ownable(msg.sender) { 
        chainId = _chainId;
    }

    function setRegisteredPeer(uint16 sourceChain, address sourceAddress) public onlyOwner() {
        registeredPeers[sourceChain] = sourceAddress;
    }

    function quoteXTransfer(
        uint16 targetChain
    ) public view returns (uint256 cost) {
        (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );
    }

    function transferFrom(address from, address to, uint256 tokenId, uint16 targetChain) payable public {
        transferFrom(from, to, tokenId);
        
        // Get the cost for the cross-chain transfer
        uint256 cost = quoteXTransfer(targetChain);
        require(msg.value >= cost);
        address targetAddress = registeredPeers[targetChain];
        require(targetAddress != address(0), "Not registered sender");
        // Initiate the cross-chain transfer
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(to, tokenId),
            0, // no receiver value needed
            GAS_LIMIT,
            chainId,
            msg.sender
        );
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        require(registeredPeers[sourceChain] == address(uint160(uint256(sourceAddress))));
        require(!_usedHash[deliveryHash]);
        _usedHash[deliveryHash] = true;
        (address to, uint256 tokenId) = abi.decode(payload, (address, uint256));

        if(_ownerOf(tokenId) == address(this)){
            transferFrom(address(this), to, tokenId);
        } else {
            _mint(to, tokenId);
        }
    }
}