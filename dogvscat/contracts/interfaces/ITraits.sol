// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITraits {
    function tokenURI(uint256 tokenId) external view returns (string memory);

    function selectTrait(
        uint16 seed,
        uint8 traitType
    ) external view returns (uint8);
}
