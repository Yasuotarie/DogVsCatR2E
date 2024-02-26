// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./interfaces/IDogVsCat.sol";
import "./interfaces/ITREATS.sol";
import "hardhat/console.sol";

contract DogVsCatMint is Ownable, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address treasury;

    IDogVsCat public nft;
    ITREATS public token;

    IERC20 public kimbo;
    IERC20 public treats;

    address public oracle;

    uint256 public kimboPaidPrice = 30 ether;
    uint256 public kimboPaidPriceWl = 20 ether;

    uint256 public avaxPaidPrice = 1.2 ether;
    uint256 public avaxPaidPriceWl = 1 ether;

    bytes32 public whitelistMerkleRoot;
    uint whitelistMaxMint = 5;
    mapping(address => uint) public whitelistClaimed;

    bytes32 public freemintMerkleRoot;
    mapping(address => bool) public freemintClaimed;

    bool public publicMintEnabled = false;

    mapping(uint256 => uint256) public tokenMintBlock;

    constructor(
        IDogVsCat _nft,
        ITREATS _token,
        IERC20 _kimbo,
        address _treasury
    ) Ownable(_msgSender()) {
        nft = _nft;
        token = _token;
        kimbo = _kimbo;
        treasury = _treasury;
        _pause();
    }

    function freemint(bytes32[] memory proof) external onlyGen0(1) {
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        require(
            MerkleProof.verify(proof, freemintMerkleRoot, leaf),
            "invalid proof"
        );

        require(!freemintClaimed[_msgSender()], "already claimed");
        freemintClaimed[_msgSender()] = true;

        _executeMint(_msgSender(), 1);
    }

    function mintWithAvax(
        uint8 amount,
        bytes32[] memory proof
    ) external payable onlyGen0(amount) {
        require(proof.length > 0 || publicMintEnabled, "whitelist only");

        uint256 totalAvaxCost = amount * avaxPaidPrice;

        // check the proof and already claimed amount
        if (proof.length > 0) {
            _verifyWhitelist(amount, proof);

            // use whistelist kimbo price
            totalAvaxCost = amount * avaxPaidPriceWl;
        }

        require(msg.value == totalAvaxCost, "invalid amount supplied");

        // transfer to the treasury
        (bool sent, ) = payable(treasury).call{value: msg.value}("");
        require(sent, "payment failed");

        _executeMint(_msgSender(), amount);
    }

    function mintWithKimbo(
        uint8 amount,
        bytes32[] memory proof
    ) external onlyGen0(amount) {
        require(proof.length > 0 || publicMintEnabled, "whitelist only");

        uint256 totalKimboCost = amount * kimboPaidPrice;

        // check the proof and already claimed amount
        if (proof.length > 0) {
            _verifyWhitelist(amount, proof);

            // use whistelist kimbo price
            totalKimboCost = amount * kimboPaidPriceWl;
        }
        
        // transfer $kimbo from the user to the treasury
        kimbo.transferFrom(_msgSender(), treasury, totalKimboCost);
        _executeMint(_msgSender(), amount);
    }

    function mintWithTreats(uint8 amount) external onlyGen1 {
        // burn the total cost for the mint
        token.burn(_msgSender(), calculateTreatsTotalCost(amount));
        

        // execute the mint
        _executeMint(_msgSender(), amount);
    }

    function simpleReveal(uint16[] memory tokenIds) external {
        
        uint targetBlock = _retrieveMintBlock(tokenIds);
        

        bytes32 targetBlockhash = blockhash(targetBlock);
        require(targetBlockhash != bytes32(0)); // invalid block hash, mut be too late

        _executeReveal(tokenIds, targetBlockhash);
    }

    function lateReveal(
        uint16[] memory tokenIds,
        bytes32 targetBlockhash,
        bytes memory signature
    ) external {
        uint targetBlock = _retrieveMintBlock(tokenIds);

        bytes32 hashData = keccak256(abi.encode(targetBlock, targetBlockhash));
        require(
            hashData.toEthSignedMessageHash().recover(signature) == oracle,
            "bad signature"
        );

        _executeReveal(tokenIds, targetBlockhash);
    }

    // OWNER FUNCTIONS
    function setPublicMintEnabled(bool _publicMintEnabled) external onlyOwner {
        publicMintEnabled = _publicMintEnabled;
    }

    function setMerkleRoot(
        bytes32 _freemintMerkleRoot,
        bytes32 _whitelistMerkleRoot
    ) external onlyOwner {
        if (_freemintMerkleRoot != "") freemintMerkleRoot = _freemintMerkleRoot;
        if (_whitelistMerkleRoot != "")
            whitelistMerkleRoot = _whitelistMerkleRoot;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // MODIFIER
    modifier onlyGen0(uint256 amount) {
        require(
            nft.minted() + amount <= nft.PAID_TOKENS(),
            "exceed gen0 supply"
        );
        _;
    }

    modifier onlyGen1() {
        require(nft.minted() >= nft.PAID_TOKENS(), "too early"); // need to test that
        _;
    }

    // INTERNAL FUNCTIONS

    function _verifyWhitelist(uint256 amount, bytes32[] memory proof) internal {
        require(amount <= whitelistMaxMint, "invalid amount supplied");

        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        require(
            MerkleProof.verify(proof, whitelistMerkleRoot, leaf),
            "invalid proof"
        );

        require(
            (whitelistClaimed[_msgSender()] + amount) <= whitelistMaxMint,
            "already claimed"
        );
        whitelistClaimed[_msgSender()] += amount;
    }

    function _executeMint(address to, uint8 amount) internal whenNotPaused {
        require(_msgSender() == tx.origin, "only EOA"); // prevent contract from calling this
        require(amount > 0, "invalid amount");

        uint16[] memory tokenIds = nft.mint(to, amount);
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenMintBlock[tokenIds[i]] = block.number;
        }
    }

    function _executeReveal(
        uint16[] memory tokenIds,
        bytes32 _blockhash
    ) internal {
        uint seed = uint256(_blockhash);
        
        nft.reveal(tokenIds, seed);
    }

    function _retrieveMintBlock(
        uint16[] memory tokenIds
    ) internal view returns (uint256 targetBlock) {
        require(tokenIds.length > 0, "invalid tokenIds");

        targetBlock = tokenMintBlock[tokenIds[0]];
        require(targetBlock != 0, "invalid token");

        // check that all tokens have the same block number
        for (uint i = 0; i < tokenIds.length; i++) {
            require(
                tokenMintBlock[tokenIds[i]] == targetBlock,
                "invalid token"
            );
            require(nft.ownerOf(tokenIds[i]) == _msgSender(), "no your token");
        }
    }

    function calculateTreatsTotalCost(
        uint8 amount
    ) public view returns (uint256 totalCost) {
        uint tokenId = nft.minted() + 1;
        for (uint i = 0; i < amount; i++) {
            totalCost += mintCostTreats(tokenId + i);
        }
    }

    function mintCostTreats(uint256 tokenId) public view returns (uint256) {
        if (tokenId <= nft.PAID_TOKENS()) return 0; // paid with kimbo
        if (tokenId <= 20_000) return 20000 ether;
        if (tokenId <= 40_000) return 40000 ether;
        return 80000 ether;
    }
}
