// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeReceiver.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract HubNFTWrapper is IWormholeReceiver, Ownable {
    IWormholeRelayer public immutable wormholeRelayer;
    address public immutable tokenAddress;
    uint16 public immutable chainId;
    uint256 constant GAS_LIMIT = 100_000;

    mapping(bytes32 deliveryHash => bool) private _usedHash;

    mapping(uint16 => address) public registeredPeers;
    mapping(address => uint256) public feeBalances;

    constructor(address _tokenAddress, address _wormholeRelayer, uint16 _chainId) Ownable(msg.sender) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        tokenAddress = _tokenAddress;
        chainId = _chainId;
    }

    function depositFees() external payable {
        feeBalances[msg.sender] += msg.value;
    }

    function withdrawFees() external {
        uint256 amount = feeBalances[msg.sender];
        require(amount > 0, "No fees to withdraw");
        
        feeBalances[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Fee withdrawal failed");
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
        IERC721(tokenAddress).transferFrom(from, to, tokenId);
        
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

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        require(msg.sender == tokenAddress, "Only accept tokens from the specified address");
        (uint16 targetChain, address to) = abi.decode(data, (uint16, address));
        require(targetChain != chainId, "Target chain cannot be the same as the current chain");
        uint256 cost = quoteXTransfer(targetChain);
        uint256 balance = feeBalances[msg.sender];
        require(balance >= cost);
        feeBalances[msg.sender] -= cost;
        address targetAddress = registeredPeers[targetChain];
        require(targetAddress != address(0), "Not registered sender");
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(to, tokenId),
            0,
            GAS_LIMIT,
            chainId,
            msg.sender
        );

        return this.onERC721Received.selector;
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
        IERC721(tokenAddress).transferFrom(address(this), to, tokenId);
    }
}