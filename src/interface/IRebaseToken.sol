// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IRebaseToken {
    function balanceOf(address account) external view returns (uint256);
    function principalBalanceOf(address account) external view returns (uint256);
    function getGlobalInterestRate() external view returns (uint256);



    function mint(address _account, uint256 _amount, uint256 _interestRate) external;
    function burn(address _account, uint256 _amount) external;
}