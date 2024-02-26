// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "./interfaces/IDogVsCat.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IBarn.sol";
import "hardhat/console.sol";

contract DogVsCat is
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ERC2981,
    AccessControl,
    IDogVsCat
{
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    uint256 public constant MAX_TOKENS = 50000;
    uint256 public constant PAID_TOKENS = 10000;

    uint16 public minted;
    uint256 public dogMinted;
    uint256 public catMinted;
    uint256 public unknownMinted;

    ITraits public traits;
    IBarn public barn;

    address public treasury;

    mapping(uint256 => AvtHtr) tokenTraits;
    mapping(uint256 => uint256) tokenMintBlock;

    constructor(address _treasury) ERC721("DogVsCat", "DGAME") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setDefaultRoyalty(_treasury, 800); // 800 equal 8%
    }

    // CONTROLLER FUNCTIONS
    function mint(
        address to,
        uint16 amount
    ) public onlyController returns (uint16[] memory tokenIds) {
        require(minted + amount <= MAX_TOKENS, "MAX SUPPLY REACHED");

        tokenIds = new uint16[](amount);
        for (uint8 i = 0; i < amount; i++) {
            tokenIds[i] = _mintSurprise(to);
        }
    }

    function reveal(
        uint16[] memory tokenIds,
        uint256 seed
    ) public onlyController {
        for (uint i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];
            uint derivedSeed = uint256(keccak256(abi.encode(seed, tokenId)));

            _reveal(tokenId, derivedSeed);
        }
    }

    // this function will only be used to complete the gen0 and start the gen1 if there is not enough mint
    function mintAndBurn(uint16 amount) public onlyAdmin {
        require(minted + amount <= PAID_TOKENS, "can't exceed the paid tokens");
        minted += amount;
    }

    // INTERNAL FUNCTIONS
    function _mintSurprise(address to) internal returns (uint16 tokenId) {
        tokenId = ++minted;

        _safeMint(to, tokenId);
        unknownMinted++;
    }

    function _reveal(uint256 tokenId, uint256 seed) internal {
        _requireOwned(tokenId);
        require(!tokenTraits[tokenId].isRevealed, "Noo.");
        
        bool isDog = _generateTraits(tokenId, seed).isDog;
        

        unknownMinted--;
        if (isDog) {
            dogMinted++;
        } else {
            catMinted++;
        }

        address owner = ownerOf(tokenId);
        address recipient = _selectRecipient(owner, seed);

        // nft stolen, transfer to new owner
        if (recipient != owner) {
            _update(recipient, tokenId, address(0));
        }
    }

    function _generateTraits(
        uint256 tokenId,
        uint256 seed
    ) internal returns (AvtHtr memory newTraits) {
        
        newTraits = tokenTraits[tokenId] = _selectTraits(seed);
    }

    function _selectTraits(
        uint256 _seed
    ) internal view returns (AvtHtr memory t) {
        uint256 seed = _seed;
        t.isRevealed = true;
        t.isDog = (seed & 0xFFFF) % 10 != 0;
        if (t.isDog) {
            seed >>= 16;
            t.background = _selectTrait(uint16(seed & 0xFFFF), 0);
            seed >>= 16;
            t.accessory = _selectTrait(uint16(seed & 0xFFFF), 1);
            seed >>= 16;
            t.body = _selectTrait(uint16(seed & 0xFFFF), 2);
            seed >>= 16;
            t.weapon = _selectTrait(uint16(seed & 0xFFFF), 3);
            seed >>= 16;
            t.head = _selectTrait(uint16(seed & 0xFFFF), 4);
        } else {
            seed >>= 16;
            t.background = _selectTrait(uint16(seed & 0xFFFF), 5);
            seed >>= 16;
            t.accessory = _selectTrait(uint16(seed & 0xFFFF), 6);
            seed >>= 16;
            t.body = _selectTrait(uint16(seed & 0xFFFF), 7);
            seed >>= 16;
            t.alphaIndex = _selectTrait(uint16(seed & 0xFFFF), 8);
        }
    }

    function _selectTrait(
        uint16 seed,
        uint8 traitType
    ) internal view returns (uint8) {
        return traits.selectTrait(seed, traitType);
    }

    function _selectRecipient(
        address initialRecipient,
        uint256 seed
    ) internal view returns (address) {
        if (minted <= PAID_TOKENS || ((seed >> 245) % 10) != 0)
            return initialRecipient; // top 10 bits haven't been used
        address thief = barn.randomCatOwner(seed >> 144); // 144 bits reserved for trait selection
        if (thief == address(0x0)) return initialRecipient;
        return thief;
    }

    // VIEW FUNCTIONS
    function getPaidTokens() external pure returns (uint256) {
        return PAID_TOKENS;
    }

    function getTokenTraits(
        uint256 tokenId
    ) external view returns (AvtHtr memory) {
        _requireOwned(tokenId);
        return tokenTraits[tokenId];
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return traits.tokenURI(tokenId);
    }

    function getTokensOf(address user) public view returns(uint256[] memory tokenIds) {
        uint balance = balanceOf(user);
        tokenIds = new uint256[](balance);

        for (uint i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }
    }

    // ADMIN FUNCTIONS
    function setBarn(IBarn _barn) external onlyAdmin {
        barn = _barn;
    }

    function setTraits(ITraits _traits) external onlyAdmin {
        traits = _traits;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    // MODIFIERS
    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    modifier onlyController() {
        _checkRole(CONTROLLER_ROLE);
        _;
    }

    // REQUIRED OVERRIDE
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0) || tokenTraits[tokenId].isRevealed, "cannot trade unrevealed nft");

        // ignore approval check if transfer to barn
        if (auth == address(barn) && to == address(barn)) {
            return super._update(to, tokenId, address(0));
        }

        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(IERC165, ERC721, ERC721Enumerable, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
