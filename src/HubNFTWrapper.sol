// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "../openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract HubNFTWrapper is IERC721Receiver {
    address public immutable tokenAddress;
    uint256 public constant chainId = 0;

    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external view override returns (bytes4) {
        require(msg.sender == tokenAddress, "Only accept tokens from the specified address");
        (uint256 destinationChainId, address to) = abi.decode(data, (uint256, address));
        // ensure chain is valid, then send NFT to destination address on chain.

        // nft locked successfully
        return this.onERC721Received.selector;
    }

    function unlockNFT(address to, uint256 tokenId) external {
        // verify vaa with wormhole, get destination and tokenId from it
        IERC721.transferFrom(address(this), to, tokenId);
    }
}