/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/

pragma solidity 0.8.9;

library USDOErrors {
    string constant RESERVE_NOT_ALLOW_DEPOSIT = "RESERVE_NOT_ALLOW_DEPOSIT";
    string constant DEPOSIT_AMOUNT_IS_ZERO = "DEPOSIT_AMOUNT_IS_ZERO";
    string constant REPAY_AMOUNT_IS_ZERO = "REPAY_AMOUNT_IS_ZERO";
    string constant WITHDRAW_AMOUNT_IS_ZERO = "WITHDRAW_AMOUNT_IS_ZERO";
    string constant LIQUIDATE_AMOUNT_IS_ZERO = "LIQUIDATE_AMOUNT_IS_ZERO";
    string constant AFTER_BORROW_ACCOUNT_IS_NOT_SAFE = "AFTER_BORROW_ACCOUNT_IS_NOT_SAFE";
    string constant AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE = "AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE";
    string constant AFTER_FLASHLOAN_ACCOUNT_IS_NOT_SAFE = "AFTER_FLASHLOAN_ACCOUNT_IS_NOT_SAFE";
    string constant EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT = "EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT";
    string constant EXCEED_THE_MAX_DEPOSIT_AMOUNT_TOTAL = "EXCEED_THE_MAX_DEPOSIT_AMOUNT_TOTAL";
    string constant EXCEED_THE_MAX_BORROW_AMOUNT_PER_ACCOUNT = "EXCEED_THE_MAX_BORROW_AMOUNT_PER_ACCOUNT";
    string constant EXCEED_THE_MAX_BORROW_AMOUNT_TOTAL = "EXCEED_THE_MAX_BORROW_AMOUNT_TOTAL";
    string constant ACCOUNT_IS_SAFE = "ACCOUNT_IS_SAFE";
    string constant WITHDRAW_AMOUNT_IS_TOO_BIG = "WITHDRAW_AMOUNT_IS_TOO_BIG";
    string constant CAN_NOT_OPERATE_ACCOUNT = "CAN_NOT_OPERATE_ACCOUNT";
    string constant LIQUIDATE_AMOUNT_IS_TOO_BIG = "LIQUIDATE_AMOUNT_IS_TOO_BIG";
    string constant SELF_LIQUIDATION_NOT_ALLOWED = "SELF_LIQUIDATION_NOT_ALLOWED";
    string constant LIQUIDATION_PRICE_PROTECTION = "LIQUIDATION_PRICE_PROTECTION";
    string constant NOT_ALLOWED_TO_EXCHANGE = "NOT_ALLOWED_TO_EXCHANGE";
    string constant NO_MORE_RESERVE_ALLOWED = "NO_MORE_RESERVE_ALLOWED";
    string constant RESERVE_PARAM_ERROR = "RESERVE_PARAM_ERROR";
    string constant REPAY_AMOUNT_NOT_ENOUGH = "REPAY_AMOUNT_NOT_ENOUGH";
    string constant INSURANCE_AMOUNT_NOT_ENOUGH = "INSURANCE_AMOUNT_NOT_ENOUGH";
    string constant LIQUIDATED_AMOUNT_NOT_ENOUGH = "LIQUIDATED_AMOUNT_NOT_ENOUGH";
}
