/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;

library DataTypes {
    struct ReserveInfo {
        //    the initial mortgage rate of collateral
        //        1e18 based decimal
        uint256 initialMortgageRate;
        //        max total deposit collateral amount
        uint256 maxTotalDepositAmount;
        //        max deposit collateral amount per account
        uint256 maxDepositAmountPerAccount;
        //        the collateral max deposit value, protect from oracle
        uint256 maxColBorrowPerAccount;
        //        oracle address
        address oracle;
        //        total deposit amount
        uint256 totalDepositAmount;
        //        liquidation mortgage rate
        uint256 liquidationMortgageRate;
        /*
            The discount rate for the liquidation.
            price * (1 - liquidationPriceOff)
            1e18 based decimal.
        */
        uint256 liquidationPriceOff;
        //         insurance fee rate
        uint256 insuranceFeeRate;
        /*       
            if the mortgage collateral delisted.
            if isFinalLiquidation = true which means user can not deposit collateral and borrow USDO
        */
        bool isFinalLiquidation;
        //        if allow user deposit collateral
        bool isDepositAllowed;
        //        if allow user borrow USDO
        bool isBorrowAllowed;
    }

    /// @notice user param
    struct UserInfo {
        //        deposit collateral ==> deposit amount
        mapping(address => uint256) depositBalance;
        
        mapping(address => bool) hasCollateral;
        //        t0 borrow USDO amount
        uint256 t0BorrowBalance;
        //        user deposit collateral list
        address[] collateralList;
    }

    struct LiquidateData {
        uint256 actualCollateral;
        uint256 insuranceFee;
        uint256 actualLiquidatedT0;
        uint256 actualLiquidated;
        uint256 liquidatedRemainUSDC;
    }
}
