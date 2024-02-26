// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IBarn.sol";
import "./interfaces/IDogVsCat.sol";
import "./interfaces/ITREATS.sol";

contract Barn is Ownable, IERC721Receiver, Pausable, IBarn {
    uint8 public constant MAX_ALPHA = 8;

    struct Stake {
        uint16 tokenId;
        address owner;
        uint80 value;
    }

    event TokenStaked(address owner, uint256 tokenId, uint256 value);
    event DogClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event CatClaimed(uint256 tokenId, uint256 earned, bool unstaked);

    IDogVsCat public nft;
    ITREATS public token;
    address public treasury;

    mapping(uint256 => Stake) public barn;
    mapping(address => uint256[]) public barnByOwner;
    mapping(uint256 => Stake[]) public pack;
    mapping(uint256 => uint256) public packIndices;

    uint256 public totalAlphaStaked = 0;
    uint256 public unaccountedRewards = 0;
    uint256 public treatsPerAlpha = 0;

    // dog must have 2 days worth of $TREATS to unstake or else it's too cold
    uint256 public constant MINIMUM_TO_EXIT = 2 days;
    // cats take a 20% tax on all $TREATS claimed
    uint256 public constant TREATS_CLAIM_TAX_PERCENTAGE = 20;
    uint256 public constant DAILY_TREATS_RATE = 10000 ether;
    uint256 public constant MAXIMUM_GLOBAL_TREATS = 2400000000 ether;
    uint256 public CLAIMING_FEE = 0.01 ether;

    uint256 public totalTreatsEarned;
    uint256 public totalDogStaked;
    uint256 public lastClaimTimestamp;

    // emergency rescue to allow unstaking without any checks but without $TREATS
    bool public rescueEnabled = false;

    constructor(
        IDogVsCat _nft,
        ITREATS _token,
        address _treasury
    ) Ownable(_msgSender()) {
        nft = _nft;
        token = _token;
        treasury = _treasury;
        _pause();
    }

    // STAKING
    function addManyToBarnAndPack(
        address account,
        uint16[] memory tokenIds
    ) external whenNotPaused {
        require(
            (account == _msgSender() && account == tx.origin) ||
                _msgSender() == address(nft),
            "DONT GIVE YOUR TOKENS AWAY"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (_msgSender() != address(nft)) {
                // dont do this step if its a mint + stake
                require(
                    nft.ownerOf(tokenIds[i]) == _msgSender(),
                    "AINT YO TOKEN"
                );
                nft.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == 0) {
                continue; // there may be gaps in the array for stolen tokens
            }

            if (isDog(tokenIds[i])) _addDogToBarn(account, tokenIds[i]);
            else _addCatToPack(account, tokenIds[i]);

            _addTokenToOwner(account, tokenIds[i]);
        }
    }

    function _addTokenToOwner(address account, uint256 tokenId) internal {
        uint256[] storage tokenIds = barnByOwner[account];
        tokenIds.push(tokenId);
    }

    function _removeTokenToOwner(address account, uint256 tokenId) internal {
        uint256[] storage tokenIds = barnByOwner[account];
        for (uint i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == tokenId) {
                tokenIds[i] = tokenIds[tokenIds.length - 1];
                tokenIds.pop();
            }
        }
    }

    function _addDogToBarn(
        address account,
        uint256 tokenId
    ) internal _updateEarnings {
        barn[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId),
            value: uint80(block.timestamp)
        });
        totalDogStaked += 1;
        emit TokenStaked(account, tokenId, block.timestamp);
    }

    function _addCatToPack(address account, uint256 tokenId) internal {
        uint256 alpha = _alphaForCat(tokenId);
        totalAlphaStaked += alpha; // Portion of earnings ranges from 8 to 5
        packIndices[tokenId] = pack[alpha].length; // Store the location of the cat in the Pack
        pack[alpha].push(
            Stake({
                owner: account,
                tokenId: uint16(tokenId),
                value: uint80(treatsPerAlpha)
            })
        ); // Add the cat to the Pack
        emit TokenStaked(account, tokenId, treatsPerAlpha);
    }

    function claimManyFromBarnAndPack(
        uint16[] memory tokenIds,
        bool unstake
    ) external payable whenNotPaused _updateEarnings {
        //payable with the tax
        require(
            msg.value >= tokenIds.length * CLAIMING_FEE,
            "you didnt pay tax"
        );
        uint256 owed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (isDog(tokenIds[i]))
                owed += _claimDogFromBarn(tokenIds[i], unstake);
            else owed += _claimCatFromPack(tokenIds[i], unstake);

            if (unstake) _removeTokenToOwner(_msgSender(), tokenIds[i]);
        }

        (bool sent, ) = treasury.call{value: msg.value}("");
        require(sent, "payment failed");

        if (owed == 0) return;
        token.mint(_msgSender(), owed);
    }

    function calculateRewards(
        uint256 tokenId
    ) external view returns (uint256 owed) {
        if (nft.getTokenTraits(tokenId).isDog) {
            Stake memory stake = barn[tokenId];
            if (totalTreatsEarned < MAXIMUM_GLOBAL_TREATS) {
                owed =
                    ((block.timestamp - stake.value) * DAILY_TREATS_RATE) /
                    1 days;
            } else if (stake.value > lastClaimTimestamp) {
                owed = 0; // $TREATS production stopped already
            } else {
                owed =
                    ((lastClaimTimestamp - stake.value) * DAILY_TREATS_RATE) /
                    1 days; // stop earning additional $TREATS if it's all been earned
            }
        } else {
            uint256 alpha = _alphaForCat(tokenId);
            Stake memory stake = pack[alpha][packIndices[tokenId]];
            owed = (alpha) * (treatsPerAlpha - stake.value);
        }
    }

    /**
     * realize $TREATS earnings for a single Dog and optionally unstake it
     * if not unstaking, pay a 20% tax to the staked Cats
     * if unstaking, there is a 50% chance all $TREATS is stolen
     * @param tokenId the ID of the Dog to claim earnings from
     * @param unstake whether or not to unstake the Dog
     * @return owed - the amount of $TREATS earned
     */
    function _claimDogFromBarn(
        uint256 tokenId,
        bool unstake
    ) internal returns (uint256 owed) {
        Stake memory stake = barn[tokenId];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        require(
            !(unstake && block.timestamp - stake.value < MINIMUM_TO_EXIT),
            "GONNA BE COLD WITHOUT TWO DAY'S TREATS"
        );
        if (totalTreatsEarned < MAXIMUM_GLOBAL_TREATS) {
            owed =
                ((block.timestamp - stake.value) * DAILY_TREATS_RATE) /
                1 days;
        } else if (stake.value > lastClaimTimestamp) {
            owed = 0; // $TREATS production stopped already
        } else {
            owed =
                ((lastClaimTimestamp - stake.value) * DAILY_TREATS_RATE) /
                1 days; // stop earning additional $TREATS if it's all been earned
        }
        if (unstake) {
            if (random(tokenId) & 1 == 1) {
                // 50% chance of all $TREATS stolen
                _payCatTax(owed);
                owed = 0;
            }
            nft.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back Dog
            delete barn[tokenId];
            totalDogStaked -= 1;
        } else {
            _payCatTax((owed * TREATS_CLAIM_TAX_PERCENTAGE) / 100); // percentage tax to staked cats
            owed = (owed * (100 - TREATS_CLAIM_TAX_PERCENTAGE)) / 100; // remainder goes to Dog owner
            barn[tokenId] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(block.timestamp)
            }); // reset stake
        }
        emit DogClaimed(tokenId, owed, unstake);
    }

    /**
     * realize $TREATS earnings for a single Cat and optionally unstake it
     * Cats earn $TREATS proportional to their Alpha rank
     * @param tokenId the ID of the cat to claim earnings from
     * @param unstake whether or not to unstake the Cat
     * @return owed - the amount of $TREATS earned
     */
    function _claimCatFromPack(
        uint256 tokenId,
        bool unstake
    ) internal returns (uint256 owed) {
        require(
            nft.ownerOf(tokenId) == address(this),
            "AINT A PART OF THE PACK"
        );
        uint256 alpha = _alphaForCat(tokenId);
        Stake memory stake = pack[alpha][packIndices[tokenId]];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        owed = (alpha) * (treatsPerAlpha - stake.value); // Calculate portion of tokens based on Alpha
        if (unstake) {
            totalAlphaStaked -= alpha; // Remove Alpha from total staked
            nft.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // Send back Cat
            Stake memory lastStake = pack[alpha][pack[alpha].length - 1];
            pack[alpha][packIndices[tokenId]] = lastStake; // Shuffle last Cat to current position
            packIndices[lastStake.tokenId] = packIndices[tokenId];
            pack[alpha].pop(); // Remove duplicate
            delete packIndices[tokenId]; // Delete old mapping
        } else {
            pack[alpha][packIndices[tokenId]] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(treatsPerAlpha)
            }); // reset stake
        }
        emit CatClaimed(tokenId, owed, unstake);
    }

    /**
     * emergency unstake tokens
     * @param tokenIds the IDs of the tokens to claim earnings from
     */
    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "RESCUE DISABLED");
        uint256 tokenId;
        Stake memory stake;
        Stake memory lastStake;
        uint256 alpha;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];

            if (isDog(tokenId)) {
                stake = barn[tokenId];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                nft.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back Dog
                delete barn[tokenId];
                totalDogStaked -= 1;
                emit DogClaimed(tokenId, 0, true);
            } else {
                alpha = _alphaForCat(tokenId);
                stake = pack[alpha][packIndices[tokenId]];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                totalAlphaStaked -= alpha; // Remove Alpha from total staked
                nft.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // Send back Cat
                lastStake = pack[alpha][pack[alpha].length - 1];
                pack[alpha][packIndices[tokenId]] = lastStake; // Shuffle last Cat to current position
                packIndices[lastStake.tokenId] = packIndices[tokenId];
                pack[alpha].pop(); // Remove duplicate
                delete packIndices[tokenId]; // Delete old mapping
                emit CatClaimed(tokenId, 0, true);
            }

            _removeTokenToOwner(_msgSender(), tokenId);
        }
    }

    /** ACCOUNTING */

    /**
     * add $TREATS to claimable pot for the Pack
     * @param amount $TREATS to add to the pot
     */
    function _payCatTax(uint256 amount) internal {
        if (totalAlphaStaked == 0) {
            // if there's no staked cats
            unaccountedRewards += amount; // keep track of $TREATS due to cats
            return;
        }
        // makes sure to include any unaccounted $TREATS
        treatsPerAlpha += (amount + unaccountedRewards) / totalAlphaStaked;
        unaccountedRewards = 0;
    }

    /**
     * tracks $TREATS earnings to ensure it stops once 2.4 billion is eclipsed
     */
    modifier _updateEarnings() {
        if (totalTreatsEarned < MAXIMUM_GLOBAL_TREATS) {
            totalTreatsEarned +=
                ((block.timestamp - lastClaimTimestamp) *
                    totalDogStaked *
                    DAILY_TREATS_RATE) /
                1 days;
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }

    /** ADMIN */

    /**
     * allows owner to enable "rescue mode"
     * simplifies accounting, prioritizes tokens out in emergency
     */
    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /** READ ONLY */

    /**
     * checks if a token is a Dog
     * @param tokenId the ID of the token to check
     * @return dog - whether or not a token is a Dog
     */
    function isDog(uint256 tokenId) public view returns (bool) {
        IDogVsCat.AvtHtr memory traits = nft.getTokenTraits(tokenId);
        return traits.isDog;
    }

    function getTokensByOwner(
        address account
    ) public view returns (uint256[] memory) {
        return barnByOwner[account];
    }

    /**
     * gets the alpha score for a Cat
     * @param tokenId the ID of the Cat to get the alpha score for
     * @return the alpha score of the Cat (5-8)
     */
    function _alphaForCat(uint256 tokenId) internal view returns (uint8) {
        IDogVsCat.AvtHtr memory traits = nft.getTokenTraits(tokenId);
        return MAX_ALPHA - traits.alphaIndex; // alpha index is 0-3
    }

    /*
     * chooses a random Cat thief when a newly minted token is stolen
     * @param seed a random value to choose a Cat from
     * @return the owner of the randomly selected Cat thief
     */
    function randomCatOwner(uint256 seed) external view returns (address) {
        if (totalAlphaStaked == 0) return address(0x0);
        uint256 bucket = (seed & 0xFFFFFFFF) % totalAlphaStaked; // choose a value from 0 to total alpha staked
        uint256 cumulative;
        seed >>= 32;
        // loop through each bucket of Cats with the same alpha score
        for (uint256 i = MAX_ALPHA - 3; i <= MAX_ALPHA; i++) {
            cumulative += pack[i].length * i;
            // if the value is not inside of that bucket, keep going
            if (bucket >= cumulative) continue;
            // get the address of a random Cat with that alpha score
            return pack[i][seed % pack[i].length].owner;
        }
        return address(0x0);
    }

    /**
     * generates a pseudorandom number
     * @param seed a value ensure different outcomes for different sources in the same block
     * @return a pseudorandom value
     */
    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        msg.sender,
                        blockhash(block.number - 1),
                        block.timestamp,
                        seed
                    )
                )
            );
    }

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to Barn directly");
        return IERC721Receiver.onERC721Received.selector;
    }
}
