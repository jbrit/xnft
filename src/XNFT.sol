// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract XNFT is ERC721 {
    uint256 private _tokenIds;

    constructor() ERC721("Cross-Chain NFT", "XNFT") {}

    function mint(address to) public returns (uint256) {
        _tokenIds++;
        _safeMint(to, _tokenIds);
        return _tokenIds;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://github.com/jbrit/xnft";
    }
}
