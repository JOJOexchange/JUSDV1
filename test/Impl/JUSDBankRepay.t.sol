// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./JUSDBankInit.t.sol";

contract JUSDBankRepayTest is JUSDBankInitTest {
    function testRepayJUSDSuccess() public {
        mockToken1.transfer(alice, 100e18);

        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        jusd.approve(address(jusdBank), 5000e6);
        jusdBank.repay(5000e6, alice);

        uint256 adjustAmount = jusdBank.getBorrowBalance(alice);
        assertEq(adjustAmount, 0);
        assertEq(jusd.balanceOf(alice), 0);
        assertEq(mockToken1.balanceOf(alice), 90e18);
        assertEq(jusdBank.getDepositBalance(address(mockToken1), alice), 10e18);
        vm.stopPrank();
    }

    function testRepayJUSDtRateSuccess() public {
        mockToken1.transfer(alice, 100e18);
        mockToken2.transfer(alice, 100e8);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        mockToken2.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(mockToken2), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(3000);
        uint256 rateT3 = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(1500e6, alice);
        jusdBank.borrow(1000e6, alice, false);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint(
            (3000e6 * 1e18) /
                rateT2 +
                1 -
                (1500e6 * 1e18) /
                rateT3 +
                (1000e6 * 1e18) /
                rateT3 +
                1
        );
        console.log((2499997149 * rateT3) / 1e18);
        vm.stopPrank();
        assertEq(aliceBorrowed, 2500001903);
    }

    function testRepayTotalJUSDtRateSuccess() public {
        mockToken1.transfer(alice, 100e18);
        vm.startPrank(address(jusdBank));
        jusd.transfer(alice, 1000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(5000e6, alice, false);
        uint256 rateT1 = jusdBank.getTRate();
        uint256 usedBorrowed = (5000e6 * 1e18) / rateT1;
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(2000);
        jusdBank.repay(6000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        uint256 rateT2 = jusdBank.getTRate();
        emit log_uint(6000e6 - ((usedBorrowed * rateT2) / 1e18 + 1));
        assertEq(jusd.balanceOf(alice), 999996829);
        assertEq(0, aliceBorrowed);
        vm.stopPrank();
    }

    function testRepayAmountisZero() public {
        mockToken1.transfer(alice, 100e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        cheats.expectRevert("REPAY_AMOUNT_IS_ZERO");
        jusdBank.repay(0, alice);
        vm.stopPrank();
    }

    // eg: emit log_uint((3000e18 * 1e18/ rateT2) * rateT2 / 1e18)
    function testRepayJUSDInSameTimestampSuccess() public {
        mockToken1.transfer(alice, 100e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(2000);
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint((3000e6 * 1e18) / rateT2);
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(3000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        assertEq(aliceUsedBorrowed, 3000e6);
        assertEq(aliceBorrowed, 0);
        vm.stopPrank();
    }

    function testRepayInSameTimestampSuccess() public {
        mockToken1.transfer(alice, 100e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        vm.warp(2000);
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        assertEq(aliceUsedBorrowed, 3000e6);
        vm.warp(2001);
        uint256 rateT3 = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(3000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint((3000e6 * 1e18) / rateT2 + 1 - (3000e6 * 1e18) / rateT3);

        assertEq(aliceBorrowed, (3 * rateT3) / 1e18);
        vm.stopPrank();
    }

    function testRepayByGeneralRepay() public {
        mockToken1.transfer(alice, 10e18);
        address[] memory userLiset = new address[](1);
        userLiset[0] = address(alice);
        uint256[] memory amountList = new uint256[](1);
        amountList[0] = 1000e6;
        USDC.mint(userLiset, amountList);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(3000e6, alice, false);

        IERC20(USDC).approve(address(generalRepay), 1000e6);
        bytes memory test;
        generalRepay.repayJUSD(address(USDC), 1000e6, alice, test);
        assertEq(jusdBank.getBorrowBalance(alice), 2000e6);
    }

    function testRepayByGeneralRepayTooBig() public {
        mockToken1.transfer(alice, 10e18);
        address[] memory userLiset = new address[](1);
        userLiset[0] = address(alice);
        uint256[] memory amountList = new uint256[](1);
        amountList[0] = 1000e6;
        USDC.mint(userLiset, amountList);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(500e6, alice, false);

        IERC20(USDC).approve(address(generalRepay), 1000e6);
        bytes memory test;
        generalRepay.repayJUSD(address(USDC), 1000e6, alice, test);
        assertEq(jusdBank.getBorrowBalance(alice), 0);
        assertEq(USDC.balanceOf(alice), 500e6);
    }

    function testRepayCollateralWallet() public {
        mockToken1.transfer(alice, 15e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(3000e6, alice, false);

        mockToken1.approve(address(generalRepay), 1e18);

        bytes memory data = swapContract.getSwapData(1e18, address(mockToken1));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            1000e6,
            data
        );
        generalRepay.repayJUSD(address(mockToken1), 1e18, alice, param);
        assertEq(jusdBank.getBorrowBalance(alice), 2000e6);
        assertEq(mockToken1.balanceOf(alice), 4e18);
    }

    function testRepayCollateralWalletTooBig() public {
        mockToken1.transfer(alice, 15e18);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(mockToken1), 10e18, alice);
        jusdBank.borrow(1000e6, alice, false);

        mockToken1.approve(address(generalRepay), 2e18);

        bytes memory data = swapContract.getSwapData(2e18, address(mockToken1));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            2000e6,
            data
        );
        generalRepay.repayJUSD(address(mockToken1), 2e18, alice, param);
        assertEq(jusdBank.getBorrowBalance(alice), 0);
        assertEq(mockToken1.balanceOf(alice), 3e18);
        assertEq(USDC.balanceOf(alice), 1000e6);
    }

    function testGeneralRepayRevert() public {
        MockERC20 usdc = new MockERC20(4000e18);
        SupportsSWAP swapContract = new SupportsSWAP(
            address(usdc),
            address(mockToken1),
            address(jojoOracle1)
        );
        IERC20(usdc).transfer(address(swapContract), 2e6);
        JUSDExchange jusdExchange = new JUSDExchange(
            address(usdc),
            address(jusd)
        );
        jusd.mint(5000e6);
        IERC20(jusd).transfer(address(jusdExchange), 5000e6);
        mockToken1.transfer(alice, 5e18);

        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 5e18);
        jusdBank.deposit(alice, address(mockToken1), 3e18, alice);
        jusdBank.borrow(300e6, alice, false);

        bytes memory data = swapContract.getSwapData(1e18, address(mockToken1));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            1000e6,
            data
        );
        mockToken1.approve(address(generalRepay), 1e18);
        cheats.expectRevert("ERC20: transfer amount exceeds balance");
        generalRepay.repayJUSD(address(mockToken1), 1e18, alice, param);
        vm.stopPrank();
    }
    // Fuzzy test
    // function testRepayFuzzyAmount(uint256 amount) public {
    //     mockToken1.transfer(alice, 100e18);
    //     jusd.transfer(alice, amount);
    //     vm.startPrank(alice);
    //     mockToken1.approve(address(jusdBank), 10e18);
    //     jusdBank.deposit(address(mockToken1), 10e18, alice);
    //     jusdBank.borrow(5000e18, alice, false, alice);
    //     jusd.approve(address(jusdBank), amount);
    //     jusdBank.repay(amount, alice);
    //     vm.stopPrank();
    // }

    // function testRepayFuzzyTo(address to) public {
    //     mockToken1.transfer(alice, 100e18);
    //     vm.startPrank(alice);
    //     mockToken1.approve(address(jusdBank), 10e18);
    //     jusdBank.deposit(address(mockToken1), 10e18, alice);
    //     jusdBank.borrow(5000e18, alice, false, alice);
    //     jusd.approve(address(jusdBank), 5000e6);
    //     jusdBank.repay(5000e18, to);
    //     vm.stopPrank();
    // }
}
