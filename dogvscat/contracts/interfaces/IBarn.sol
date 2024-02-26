// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBarn {
    function randomCatOwner(uint256 seed) external view returns (address);

    function addManyToBarnAndPack(
        address account,
        uint16[] memory tokenIds
    ) external;
}
