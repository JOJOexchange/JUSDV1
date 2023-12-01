// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@JOJO/contracts/testSupport/TestERC20.sol";
import "../../src/oracle/UniswapPriceAdaptor.sol";
import "../mocks/MockEmergencyOracle.sol";
import "../mocks/MockUniswapOracle.sol";
import "./JUSDBankInit.t.sol";

contract JUSDViewTest is JUSDBankInitTest {
    function testJUSDView() public {
        TestERC20 BTC = new TestERC20("BTC", "BTC", 8);
        MockUniswapOracle MockUni = new MockUniswapOracle();
        MockEmergencyOracle mockE = new MockEmergencyOracle();
        address[] memory pools;
        UniswapPriceAdaptor UNIOracle = new UniswapPriceAdaptor(
            address(MockUni),
            18,
            address(BTC),
            address(USDC),
            pools,
            600,
            address(mockE),
            50000000000000000
        );
        cheats.expectRevert("deviation is too big");
        UNIOracle.getAssetPrice();
        jojoOracle2 = new JOJOOracleAdaptor(
            address(mockToken1ChainLink),
            10,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.initReserve(
            // token
            address(BTC),
            // maxCurrencyBorrowRate
            7e17,
            // maxDepositAmount
            2100e8,
            // maxDepositAmountPerAccount
            210e8,
            // maxBorrowValue
            100000e18,
            // liquidateMortgageRate
            75e16,
            // liquidationPriceOff
            1e17,
            // insuranceFeeRate
            1e17,
            address(jojoOracle2)
        );
        uint256 btcPrice = IPriceChainLink(address(jojoOracle2))
            .getAssetPrice();
        console.log("btcPrice", btcPrice);
        address[] memory user = new address[](1);
        user[0] = address(alice);
        uint256[] memory amountList = new uint256[](1);
        amountList[0] = 10e8;
        BTC.mint(user, amountList);
        mockToken1.transfer(alice, 100e18);

        vm.startPrank(alice);

        BTC.approve(address(jusdBank), 1e8);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.deposit(alice, address(BTC), 1e8, alice);

        uint256 maxMintAmount = jusdBank.getDepositMaxMintAmount(alice);
        uint256 maxWithdrawBTC = jusdBank.getMaxWithdrawAmount(
            address(BTC),
            alice
        );
        uint256 maxWithdrawETH = jusdBank.getMaxWithdrawAmount(
            address(mockToken1),
            alice
        );
        assertEq(maxMintAmount, 8700000000);
        assertEq(maxWithdrawBTC, 1e8);
        assertEq(maxWithdrawETH, 10e18);

        jusdBank.borrow(7200e6, alice, false);
        maxWithdrawBTC = jusdBank.getMaxWithdrawAmount(address(BTC), alice);
        maxWithdrawETH = jusdBank.getMaxWithdrawAmount(
            address(mockToken1),
            alice
        );
        assertEq(maxWithdrawBTC, 100000000);
        assertEq(maxWithdrawETH, 1875000000000000000);

        jusdBank.borrow(800e6, alice, false);
        jusdBank.withdraw(address(BTC), 1e8, alice, false);
        maxWithdrawETH = jusdBank.getMaxWithdrawAmount(
            address(mockToken1),
            alice
        );
        assertEq(maxWithdrawETH, 0);
    }
}
