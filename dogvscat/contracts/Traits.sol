// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IDogVsCat.sol";
import "hardhat/console.sol";

contract Traits is Ownable, ITraits {
    using Strings for uint256;

    uint256 private alphaTypeIndex = 8;

    // struct to store each trait's data for metadata and rendering
    struct Trait {
        string name;
        string png;
    }

    // mapping from trait type (index) to its name
    string[9] _traitTypes = [
        // for dog:
        "Background",
        "Accessory",
        "Body",
        "Weapon",
        "Head"
    ];
    // storage of each traits name and base64 PNG data
    mapping(uint8 => mapping(uint8 => Trait)) public traitData;
    mapping(uint8 => uint8) public traitCountForType;
    // mapping from alphaIndex to its score
    string[4] _alphas = ["8", "7", "6", "5"];

    IDogVsCat public nft;

    string public unrevealedTokenURI;


    constructor() Ownable(_msgSender()) {}

    function selectTrait(
        uint16 seed,
        uint8 traitType
    ) external view override returns (uint8) {
        if (traitType == alphaTypeIndex) {
            uint256 m = seed % 100;
            if (m > 95) {
                return 0;
            } else if (m > 80) {
                return 1;
            } else if (m > 50) {
                return 2;
            } else {
                return 3;
            }
        }
        uint8 modOf = traitCountForType[traitType];
        

        return uint8(seed % modOf);
    }

    /***ADMIN */

    function setNft(address _nft) external onlyOwner {
        nft = IDogVsCat(_nft);
    }

    function setUnrevealedTokenURI(string memory _unrevealedTokenURI) external onlyOwner {
        unrevealedTokenURI = _unrevealedTokenURI;
    }

    /**
     * administrative to upload the names and images associated with each trait
     * @param traitType the trait type to upload the traits for (see traitTypes for a mapping)
     * @param traits the names and base64 encoded PNGs for each trait
     */

    function uploadTraits(
        uint8 traitType,
        uint8[] calldata traitIds,
        Trait[] calldata traits
    ) external onlyOwner {
        require(traitIds.length == traits.length, "Mismatched inputs");

        for (uint256 i = 0; i < traits.length; i++) {
            traitData[traitType][traitIds[i]] = Trait(
                traits[i].name,
                traits[i].png
            );
        }
    }

    function setTraitCountForType(
        uint8[] memory _tType,
        uint8[] memory _len
    ) public onlyOwner {
        for (uint256 i = 0; i < _tType.length; i++) {
            traitCountForType[_tType[i]] = _len[i];
        }
    }

    /***RENDER */

    /**
     * generates an <image> element using base64 encoded PNGs
     * @param trait the trait storing the PNG data
     * @return the <image> element
     */
    function drawTrait(
        Trait memory trait
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<image x="0" y="0" width="200" height="200" image-rendering="pixelated" preserveAspectRatio="xMidYMid" xlink:href="data:image/png;base64,',
                    trait.png,
                    '"/>'
                )
            );
    }

    function draw(string memory png) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<image x="0" y="0" width="200" height="200" image-rendering="pixelated" preserveAspectRatio="xMidYMid" xlink:href="data:image/png;base64,',
                    png,
                    '"/>'
                )
            );
    }

    /**
     * generates an entire SVG by composing multiple <image> elements of PNGs
     * @param tokenId the ID of the token to generate an SVG for
     * @return a valid SVG of the Dog / Cat
     */

    function drawSVG(uint256 tokenId) public view returns (string memory) {
        IDogVsCat.AvtHtr memory s = nft.getTokenTraits(tokenId);

        string memory svgString = "";
        if (s.isDog) {
            svgString = string(
                abi.encodePacked(
                    drawTrait(traitData[0][s.background]),
                    drawTrait(traitData[1][s.accessory]),
                    drawTrait(traitData[2][s.body]),
                    drawTrait(traitData[3][s.weapon]),
                    drawTrait(traitData[4][s.head])
                )
            );
        } else {
            svgString = string(
                abi.encodePacked(
                    drawTrait(traitData[5][s.background]),
                    drawTrait(traitData[6][s.accessory]),
                    drawTrait(traitData[7][s.body]),
                    drawTrait(traitData[8][s.alphaIndex])
                )
            );
        }

        return
            string(
                abi.encodePacked(
                    '<svg id="cat" width="100%" height="100%" version="1.1" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
                    svgString,
                    "</svg>"
                )
            );
    }

    /**
     * generates an attribute for the attributes array in the ERC721 metadata standard
     * @param traitType the trait type to reference as the metadata key
     * @param value the token's trait associated with the key
     * @return a JSON dictionary for the single attribute
     */
    function attributeForTypeAndValue(
        string memory traitType,
        string memory value
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '{"trait_type":"',
                    traitType,
                    '","value":"',
                    value,
                    '"}'
                )
            );
    }

    function _compileTraits(
        uint256 tokenId
    ) internal view returns (string memory traits) {
        IDogVsCat.AvtHtr memory s = nft.getTokenTraits(tokenId);

        if (!s.isRevealed) {
            return "";
        }

        if (s.isDog) {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue("Type", "Dog"),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[0],
                        traitData[0][s.background % traitCountForType[0]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[1],
                        traitData[1][s.accessory % traitCountForType[1]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[2],
                        traitData[2][s.body % traitCountForType[2]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[3],
                        traitData[3][s.weapon % traitCountForType[3]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[4],
                        traitData[4][s.head % traitCountForType[4]].name
                    ),
                    ","
                )
            );
        } else {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue("Type", "Cat"),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[0],
                        traitData[5][s.background % traitCountForType[5]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[1],
                        traitData[6][s.accessory % traitCountForType[6]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        _traitTypes[2],
                        traitData[7][s.body % traitCountForType[7]].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Alpha Score",
                        _alphas[s.alphaIndex]
                    ),
                    ","
                )
            );
        }
    }

    function _compileImage(uint256 tokenId) internal view returns (string memory) {
        IDogVsCat.AvtHtr memory s = nft.getTokenTraits(tokenId);
        if (!s.isRevealed) {
            return unrevealedTokenURI;
        }

        return string(abi.encodePacked('data:image/svg+xml;base64,', base64(bytes(drawSVG(tokenId)))));
    }

    /**
     * generates an array composed of all the individual traits and values
     * @param tokenId the ID of the token to compose the metadata for
     * @return a JSON array of all of the attributes for given token ID
     */
    function compileAttributes(
        uint256 tokenId
    ) public view returns (string memory) {
        IDogVsCat.AvtHtr memory s = nft.getTokenTraits(tokenId);
        string memory traits = _compileTraits(tokenId);

        return
            string(
                abi.encodePacked(
                    "[",
                    traits,
                    '{"trait_type":"Generation","value":',
                    tokenId <= nft.PAID_TOKENS() ? '"Gen 0"' : '"Gen 1"',
                    '},{"trait_type":"Is Revealed","value":',
                    s.isRevealed ? '"Yes"' : '"No"',
                    "}]"
                )
            );
    }

    /**
     * generates a base64 encoded metadata response without referencing off-chain content
     * @param tokenId the ID of the token to generate the metadata for
     * @return a base64 encoded JSON dictionary of the token's metadata and SVG
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        IDogVsCat.AvtHtr memory s = nft.getTokenTraits(tokenId);

        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                s.isRevealed
                    ? (s.isDog ? "Dog #" : "Cat #")
                    : "Unrevealed #",
                tokenId.toString(),
                '", "description": "Thousands of dogs and Cats compete on a farm in the metaverse. A tempting prize of $Treats awaits, with deadly high stakes. All the metadata and images are generated and stored 100% on-chain. No IPFS. NO API. Just the Avalanche blockchain.", "image": "',
                _compileImage(tokenId),
                '", "attributes":',
                compileAttributes(tokenId),
                "}"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    base64(bytes(metadata))
                )
            );
    }

    /***BASE 64 - Written by Brech Devos */

    string internal constant TABLE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 3 bytes at a time
            for {

            } lt(dataPtr, endPtr) {

            } {
                dataPtr := add(dataPtr, 3)

                // read 3 bytes
                let input := mload(dataPtr)

                // write 4 characters
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(input, 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(data), 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
        }

        return result;
    }
}
