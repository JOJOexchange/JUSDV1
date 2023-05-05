// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./JUSDBankInit.t.sol";

contract JUSDBankWithdrawTest is JUSDBankInitTest {
    function testWithdrawAmountIsZero() public {
        mockToken1.transfer(alice, 10e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        cheats.expectRevert("WITHDRAW_AMOUNT_IS_ZERO");
        jusdBank.withdraw(address(mockToken1), 0, alice, false);
    }

    function testWithdrawAmountEasy() public {
        mockToken1.transfer(alice, 10e18);
        mockToken2.transfer(alice, 20e8);
        mockToken2.transfer(bob, 20e8);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 20e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        jusdBank.borrow(4000e6, alice, false);
        uint256 maxToken2 = jusdBank.getMaxWithdrawAmount(
            address(mockToken2),
            alice
        );
        assertEq(maxToken2, 10e8);
        jusdBank.withdraw(address(mockToken1), 10e18, alice, false);
        uint256 maxToken1 = jusdBank.getMaxWithdrawAmount(
            address(mockToken1),
            alice
        );
        assertEq(maxToken1, 0);

        vm.stopPrank();
        vm.startPrank(bob);
        mockToken2.approve(address(jusdBank), 20e8);
        jusdBank.deposit(bob, address(mockToken2), 10e8, alice);
    }

    function testWithdrawWithdrawAmountIsTooBig() public {
        mockToken1.transfer(alice, 10e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        cheats.expectRevert("WITHDRAW_AMOUNT_IS_TOO_BIG");
        jusdBank.withdraw(address(mockToken1), 11e18, alice, false);
    }

    function testWithDrawSuccess() public {
        mockToken1.transfer(alice, 10e18);
        mockToken2.transfer(alice, 10e8);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        jusdBank.borrow(5000e6, alice, false);
        uint256 rate = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 5000e6);
        vm.warp(3000);
        jusdBank.withdraw(address(mockToken1), 1e18, alice, false);
        uint256 rate2 = jusdBank.getTRate();
        uint256 maxToken2 = jusdBank.getMaxWithdrawAmount(
            address(mockToken2),
            alice
        );
        emit log_uint(
            ((8500e6 - jusdBank.getBorrowBalance(alice)) * 1e18) /
                ((5e17 * 800000000) / 1e18)
        );
        emit log_uint((5000e6 * 1e18) / rate);
        emit log_uint(jojoOracle2.getAssetPrice());
        uint256 balance = mockToken1.balanceOf(alice);
        uint256 aliceJusd = jusdBank.getBorrowBalance(alice);
        emit log_uint(aliceJusd);
        uint256 maxMint = jusdBank.getDepositMaxMintAmount(alice);
        assertEq(balance, 1e18);
        assertEq(aliceJusd, (4999993662 * rate2) / 1e18);
        assertEq(maxMint, 107200e6);
        assertEq(maxToken2, 1000000000);
        vm.stopPrank();
    }

    function testWithDrawlNotMax() public {
        mockToken1.transfer(alice, 10e18);
        mockToken2.transfer(alice, 10e8);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        jusdBank.borrow(6000e6, alice, false);
        uint256 rateT2 = jusdBank.tRate();
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(3000);
        jusdBank.repay(5000e6, alice);
        uint256 rateT3 = jusdBank.tRate();
        jusdBank.withdraw(address(mockToken1), 5, alice, false);
        jusdBank.withdraw(address(mockToken2), 5, alice, false);
        emit log_uint((6000e6 * 1e18) / rateT2 + 1 - (5000e6 * 1e18) / rateT3);

        uint256 balance1 = mockToken1.balanceOf(alice);
        uint256 balance2 = mockToken2.balanceOf(alice);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        assertEq(balance1, 5);
        assertEq(aliceBorrow, (1000001904 * rateT3) / 1e18);
        assertEq(balance2, 5);
        vm.stopPrank();
    }

    function testWithDrawFailNotMax() public {
        mockToken1.transfer(alice, 10e18);
        mockToken2.transfer(alice, 10e8);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        vm.warp(2000);
        jusdBank.borrow(6000e6, alice, false);
        vm.warp(3000);
        jusdBank.withdraw(address(mockToken1), 10e18, alice, false);
        cheats.expectRevert("AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.withdraw(address(mockToken2), 10e8, alice, false);
        vm.stopPrank();
    }

    function testRepayAndWithdrawAll() public {
        mockToken2.transfer(alice, 10e8);
        mockToken1.transfer(alice, 100e18);

        vm.startPrank(address(jusdBank));
        jusd.transfer(alice, 1000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        vm.warp(1000);
        jusdBank.borrow(5000e6, alice, false);
        uint256 rateT2 = jusdBank.tRate();
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(2000);
        jusdBank.repay(6000e6, alice);
        jusdBank.withdraw(address(mockToken1), 10e18, alice, false);
        uint256 adjustAmount = jusdBank.getBorrowBalance(alice);
        uint256 rateT3 = jusdBank.tRate();
        emit log_uint(
            6000e6 - (((5000e6 * 1e18) / rateT2 + 1) * rateT3) / 1e18
        );
        assertEq(jusd.balanceOf(alice), 999996829);
        assertEq(0, adjustAmount);
        assertEq(100e18, mockToken1.balanceOf(alice));
        assertEq(
            false,
            jusdBank.getIfHasCollateral(alice, address(mockToken1))
        );
        vm.stopPrank();
    }

    function testDepositTooManyThenWithdraw() public {
        jusdBank.updateReserveParam(
            address(mockToken1),
            8e17,
            2300e18,
            230e18,
            100000e18
        );
        jusdBank.updateMaxBorrowAmount(200000e18, 300000e18);
        mockToken1.transfer(alice, 200e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 200e18);
        jusdBank.deposit(alice, address(mockToken1), 200e18, alice);
        jusdBank.borrow(100000e6, alice, false);
        uint256 withdrawAmount = jusdBank.getMaxWithdrawAmount(
            address(mockToken1),
            alice
        );
        assertEq(withdrawAmount, 75e18);
        jusdBank.withdraw(address(mockToken1), 75e18, alice, false);
        vm.stopPrank();
    }

    function testWithdrawInternal() public {
        mockToken1.transfer(alice, 10e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.withdraw(address(mockToken1), 1e18, bob, true);
        assertEq(
            IJUSDBank(jusdBank).getDepositBalance(address(mockToken1), bob),
            1e18
        );
    }

    function testWithdrawInternalExceed() public {
        mockToken1.transfer(alice, 10e18);
        mockToken1.transfer(bob, 2030e18);

        vm.startPrank(bob);
        mockToken1.approve(address(jusdBank), 2030e18);
        jusdBank.deposit(bob, address(mockToken1), 2030e18, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        cheats.expectRevert("EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT");
        jusdBank.withdraw(address(mockToken1), 10e18, bob, true);
    }

    // Fuzzy test
    // function testWithdrawCollateral(address collateral) public {
    //     vm.startPrank(alice);
    //     jusdBank.withdraw(collateral, 11e18, alice, alice);
    // }

    // function testWithdrawAmount(uint256 amount) public {
    //     mockToken1.transfer(alice, 10e18);
    //     vm.startPrank(alice);
    //     mockToken1.approve(address(jusdBank), 10e18);
    //     jusdBank.deposit(address(mockToken1), 10e18, alice);
    //     jusdBank.withdraw(address(mockToken1), amount, alice, alice);
    // }

    // function testWithdrawTo(address to) public {
    //     mockToken1.transfer(alice, 10e18);
    //     vm.startPrank(alice);
    //     mockToken1.approve(address(jusdBank), 10e18);
    //     jusdBank.deposit(address(mockToken1), 10e18, alice);
    //     jusdBank.withdraw(address(mockToken1), 10e18, to, alice);
    // }

    // function testWithdrawFrom(address from) public {
    //     mockToken1.transfer(alice, 10e18);
    //     vm.startPrank(alice);
    //     mockToken1.approve(address(jusdBank), 10e18);
    //     jusdBank.deposit(address(mockToken1), 10e18, alice);
    //     jusdBank.withdraw(address(mockToken1), 10e18, alice, from);
    // }
}
