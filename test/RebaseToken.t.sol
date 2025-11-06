// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    address alice;
    address user;
    Vault vault;

    function setUp() public {
        rebaseToken = new RebaseToken();
        rebaseToken.grantMinterBurnerRole(address(this));
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMinterBurnerRole(address(vault));

        alice = makeAddr("alice");
        user = makeAddr("user");
    }

    function testMint() public {
        uint256 interest = rebaseToken.getGlobalInterestRate();
        uint256 mintAmount = 100 ether;
        //  first mint
        rebaseToken.mint(alice, mintAmount, interest);
        assertEq(rebaseToken.principalBalanceOf(alice), mintAmount);

        console.log("start second mint");
        uint256 initialTimestamp = block.timestamp;

        //  after 1 hour, mint again
        vm.warp(initialTimestamp + 3600);

        uint256 balanceBeforeSecondMint = rebaseToken.balanceOf(alice);
        uint256 interestAccrued = balanceBeforeSecondMint - mintAmount;

        console.log("interestAccrued", interestAccrued);
        rebaseToken.mint(alice, mintAmount, interest);
        assertEq(
            rebaseToken.principalBalanceOf(alice),
            mintAmount * 2 + interestAccrued
        );
    }

    function testDepositLinear(uint256 amount) public {
        // Deposit funds
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance", middleBalance);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(
            endBalance - middleBalance,
            middleBalance - startBalance,
            1
        );

        vm.stopPrank();
    }

    function testWrap() public {
        uint256 initialTimestamp = block.timestamp;
        console.log("initialTimestamp", initialTimestamp);
        vm.warp(initialTimestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        console.log("block.timestamp", block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        assertEq(block.timestamp, initialTimestamp + 2 hours);
    }
}
