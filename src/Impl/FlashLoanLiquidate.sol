/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;

import "../../src/Interface/IJUSDBank.sol";
import "../../src/Interface/IJUSDExchange.sol";
import "../../src/Interface/IFlashLoanReceive.sol";
import {DecimalMath} from "../lib/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceChainLink} from "../Interface/IPriceChainLink.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FlashLoanLiquidate is IFlashLoanReceive {
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    address public usdoBank;
    address public usdoExchange;
    address public immutable USDC;
    address public immutable JUSD;
    address public insurance;

    struct LiquidateData {
        uint256 actualCollateral;
        uint256 insuranceFee;
        uint256 actualLiquidatedT0;
        uint256 actualLiquidated;
        uint256 liquidatedRemainUSDC;
    }

    constructor(
        address _usdoBank,
        address _usdoExchange,
        address _USDC,
        address _JUSD,
        address _insurance
    ) {
        usdoBank = _usdoBank;
        usdoExchange = _usdoExchange;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    function JOJOFlashLoan(
        address asset,
        uint256 amount,
        address to,
        bytes calldata param
    ) external {
        //dodo swap
        (LiquidateData memory liquidateData, bytes memory originParam) = abi
            .decode(param, (LiquidateData, bytes));
        (
            address approveTarget,
            address swapTarget,
            address liquidator,
            bytes memory data
        ) = abi.decode(originParam, (address, address, address, bytes));
        IERC20(asset).approve(approveTarget, amount);
        (bool success, ) = swapTarget.call(data);
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        uint256 USDCAmount = IERC20(USDC).balanceOf(address(this));

        IERC20(USDC).approve(usdoExchange, liquidateData.actualLiquidated);
        IJUSDExchange(usdoExchange).buyJUSD(
            liquidateData.actualLiquidated,
            address(this)
        );
        IERC20(JUSD).approve(usdoBank, liquidateData.actualLiquidated);
        IJUSDBank(usdoBank).repay(liquidateData.actualLiquidated, to);

        // 2. insurance
        IERC20(USDC).safeTransfer(insurance, liquidateData.insuranceFee);
        // 3. liquidate usdc
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(USDC).safeTransfer(to, liquidateData.liquidatedRemainUSDC);
        }
        // 4. transfer to liquidator
        IERC20(USDC).safeTransfer(
            liquidator,
            USDCAmount -
                liquidateData.insuranceFee -
                liquidateData.actualLiquidated -
                liquidateData.liquidatedRemainUSDC
        );
    }
}
