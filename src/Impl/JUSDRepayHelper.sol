/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "./JUSDBank.sol";

pragma solidity 0.8.9;

contract JUSDRepayHelper is Ownable {
    address public immutable JusdBank;
    address public immutable JUSD;

    mapping(address => bool) public adminWhiteList;


    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    event HelpToTransfer(address from, address to, uint256 amount);
    event UpdateAdmin(address admin,  bool isValid);
    // =========================Consturct===================

    constructor(address _jusdBank, address _JUSD) Ownable() {
        // set params
        JusdBank = _jusdBank;
        JUSD = _JUSD;
        IERC20(JUSD).approve(JusdBank, type(uint256).max);
    }

    modifier onlyAdminWhiteList() {
        require(adminWhiteList[msg.sender], "caller is not in the admin white list");
        _;
    }

    function repayToBank(address from, address to) onlyAdminWhiteList external {
        uint256 balance = IERC20(JUSD).balanceOf(address(this));
        require(balance >= 0, "do not have JUSD");
        IJUSDBank(JusdBank).repay(balance, to);
        emit HelpToTransfer(from, to, balance);
    }

    function setWhiteList(address admin, bool isValid) public onlyOwner {
        adminWhiteList[admin] = isValid;
        emit UpdateAdmin(admin, isValid);
    }

}
