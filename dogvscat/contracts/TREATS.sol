// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ITREATS.sol";

contract TREATS is ERC20, AccessControl, ITREATS {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    constructor(address _treasury) ERC20("Treats", "TREATS") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // mint 600m for potential development like airdrop, burn, or to add liquidity
        _mint(_treasury, 600_000_000 ether);
    }

    function addressof() public view returns(address){
        return msg.sender;
    }

    // CONTROLLER
    function mint(address to, uint256 amount) public override onlyController {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public override onlyController {
        _burn(from, amount);
    }

    // MODIFIER
    modifier onlyController() {
        _checkRole(CONTROLLER_ROLE);
        _;
    }

    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }
}
