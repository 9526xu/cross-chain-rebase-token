// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IRebaseToken} from "./interface/IRebaseToken.sol";



contract Value {

    IRebaseToken public immutable rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        rebaseToken = _rebaseToken;
    }


    function deposit() public payable {
        uint256 amount=msg.value;
        rebaseToken.mint(msg.sender, amount, rebaseToken.getGlobalInterestRate());
        emit Deposit(msg.sender, amount);
    }

    function redeem(uint256 _amount) public {
        if (_amount == type(uint256).max) {
            _amount=rebaseToken.balanceOf(msg.sender);
        }

        rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, "Redeem failed");
        emit Redeem(msg.sender, _amount);
    }
}
