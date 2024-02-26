// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IDogVsCat is IERC721, IERC721Enumerable {
    struct AvtHtr {
        bool isRevealed;
        bool isDog;
        uint8 background;
        uint8 accessory;
        uint8 body;
        uint8 weapon;
        uint8 head;
        uint8 alphaIndex;
    }

    function mint(
        address to,
        uint16 amount
    ) external returns (uint16[] memory tokenIds);

    function reveal(uint16[] memory tokenIds, uint256 seed) external;

    function minted() external view returns (uint16);

    function MAX_TOKENS() external view returns (uint256);

    function PAID_TOKENS() external view returns (uint256);

    function getTokenTraits(
        uint256 tokenId
    ) external view returns (AvtHtr memory);
}
