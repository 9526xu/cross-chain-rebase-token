// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE");

    mapping(address => uint256) private s_userInterestRate; // record user interest rate
    mapping(address => uint256) private s_userLastUpdatedTimestamp; // record user last updated timestamp

    uint256 private constant PRECISION_FACTOR = 1e18; // 100% = 1e18

    uint256 private s_globalInterestRate = 5e10; // record global interest rate

    constructor() ERC20("RebaseToken", "RT") Ownable(msg.sender) {}

    event InterestSet(uint256 interestRate);

    function grantMinterBurnerRole(address _account) public onlyOwner {
        grantRole(MINTER_BURNER_ROLE, _account);
    }

    /**
     * @notice Get user balance with accumulated interest
     * @param account User address
     * @return Balance of user with accumulated interest
     */
    function balanceOf(address account) public view override returns (uint256) {
        uint256 principalBalance = super.balanceOf(account);
        if (principalBalance == 0) {
            return 0;
        }
        // calculate user accumulated interest rate since last update equation:
        // balance * (1 + (interestRate * timeElapsed))
        return principalBalance * _calculateUserAccumulatedInterestRateSinceLastUpdate(account) / PRECISION_FACTOR;
    }

    /**
     * @notice Mint user balance with accumulated interest
     * @param _account User address
     * @param _amount Amount to mint
     * @param _interestRate Interest rate to mint
     */
    function mint(address _account, uint256 _amount, uint256 _interestRate) public onlyRole(MINTER_BURNER_ROLE) {
        _mintUserInterestAndUpdateTimestamp(_account);
        s_userInterestRate[_account] = _interestRate;
        _mint(_account, _amount);
    }

    /**
     * @notice Burn user balance with accumulated interest
     * @param _account User address
     * @param _amount Amount to burn
     */
    function burn(address _account, uint256 _amount) public onlyRole(MINTER_BURNER_ROLE) {
        //  if amount is max, burn all
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_account);
        }

        _mintUserInterestAndUpdateTimestamp(_account);
        _burn(_account, _amount);
    }

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        address from = _msgSender();
        // if amount is max, transfer all balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(from);
        }
        _beforeTokenTransfer(from, _to, _amount);
        return super.transfer(_to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        // if amount is max, transfer all balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _beforeTokenTransfer(_from, _to, _amount);
        return super.transferFrom(_from, _to, _amount);
    }

    function getGlobalInterestRate() public view returns (uint256) {
        return s_globalInterestRate;
    }

    /**
     * @notice Get user interest rate
     * @param account User address
     * @return User interest rate
     */
    function getUserInterestRate(address account) public view returns (uint256) {
        return s_userInterestRate[account];
    }

    /**
     * @notice Hook that is called before any token transfer. This includes calls to {transfer} and
     * {transferFrom}.
     *
     * @param _from The address from which the token is transferred.
     * @param _to The address to which the token is transferred.
     * @param _amount The amount of the token to be transferred.
     */
    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal {
        _mintUserInterestAndUpdateTimestamp(_from);
        _mintUserInterestAndUpdateTimestamp(_to);
        if (s_userInterestRate[_to] == 0) {
            s_userInterestRate[_to] = s_userInterestRate[_from];
        }
    }

    /**
     * @notice Get user principal balance
     * @param account User address
     * @return Principal balance of user
     */
    function principalBalanceOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @notice Set new global interest rate,the new global interest rate only decrease
     * @param _newGlobalInterestRate New global interest rate decrease
     */
    function setNewGlobalInterestRate(uint256 _newGlobalInterestRate) public onlyOwner {
        if (_newGlobalInterestRate >= s_globalInterestRate) {
            revert("New global interest rate cannot be 0");
        }
        s_globalInterestRate = _newGlobalInterestRate;
        emit InterestSet(_newGlobalInterestRate);
    }

    /**
     * @notice Mint user interest and update timestamp
     * @param account User address
     */
    function _mintUserInterestAndUpdateTimestamp(address account) internal {
        uint256 principalBalance = super.balanceOf(account);
        uint256 currentBalance = balanceOf(account);
        uint256 increaseBalance = currentBalance - principalBalance;
        // mint user interest
        _mint(account, increaseBalance);
        s_userLastUpdatedTimestamp[account] = block.timestamp;
    }

    /**
     * @notice Calculate user accumulated interest rate since last update
     * @param account User address
     * @return Accumulated interest rate of user since last update
     */
    function _calculateUserAccumulatedInterestRateSinceLastUpdate(address account) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[account];
        // 1 + (interestRate * timeElapsed)
        uint256 accumulatedInterestRate = PRECISION_FACTOR + (s_userInterestRate[account] * timeElapsed);
        return accumulatedInterestRate;
    }
}
