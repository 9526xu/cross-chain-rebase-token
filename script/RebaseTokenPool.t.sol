// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

contract RebaseTokenPoolTest is Test {
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;
    address owner;
}
