// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "ds-test/test.sol";
import "../../src/Impl/JUSDBank.sol";
import "../mocks/MockERC20.sol";
import "../../src/token/JUSD.sol";
import "../../src/Testsupport/SupportsSWAP.sol";
import "../mocks/MockChainLink500.sol";
import "../../src/oracle/JOJOOracleAdaptor.sol";
import "../../src/Impl/flashloanImpl/FlashLoanLiquidate.sol";
import "../mocks/MockChainLink.t.sol";
import "../mocks/MockJOJODealer.sol";
import "../../src/lib/DataTypes.sol";
import "@JOJO/contracts/subaccount/Subaccount.sol";
import "@JOJO/contracts/impl/JOJODealer.sol";
import "@JOJO/contracts/subaccount/SubaccountFactory.sol";
import "@JOJO/contracts/testSupport/TestERC20.sol";
import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/Impl/JUSDExchange.sol";
import "../mocks/MockChainLinkBadDebt.sol";
import "../../src/lib/DecimalMath.sol";
import "../mocks/MockChainLink900.sol";
import "../mocks/MockUSDCPrice.sol";
import {LiquidateCollateralRepayNotEnough, LiquidateCollateralInsuranceNotEnough, LiquidateCollateralLiquidatedNotEnough} from "../mocks/MockWrongLiquidateFlashloan.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

contract JUSDBankOperatorLiquidateTest is Test {
    Cheats internal constant cheats =
        Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    using DecimalMath for uint256;

    JUSDBank public jusdBank;
    MockERC20 public ETH;
    TestERC20 public USDC;
    JUSD public jusd;
    JOJOOracleAdaptor public jojoOracleETH;
    MockChainLink public ethChainLink;
    MockUSDCPrice public usdcPrice;
    JOJODealer public jojoDealer;
    SubaccountFactory public subaccountFactory;
    JUSDExchange public jusdExchange;
    SupportsSWAP public swapContract;

    address internal alice = address(1);
    address internal bob = address(2);
    address internal jim = address(4);
    address internal insurance = address(3);

    function setUp() public {
        ETH = new MockERC20(2000e18);
        jusd = new JUSD(6);
        USDC = new TestERC20("USDC", "USDC", 6);
        ethChainLink = new MockChainLink();
        usdcPrice = new MockUSDCPrice();
        subaccountFactory = new SubaccountFactory();
        jojoDealer = new JOJODealer(address(USDC));
        jojoOracleETH = new JOJOOracleAdaptor(
            address(ethChainLink),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(insurance, "Insurance");
        jusd.mint(300000e6);
        jusdExchange = new JUSDExchange(address(USDC), address(jusd));
        jusd.transfer(address(jusdExchange), 100000e6);
        jusdBank = new JUSDBank( // maxReservesAmount_
            10,
            insurance,
            address(jusd),
            address(jojoDealer),
            // maxBorrowAmountPerAccount_
            100000000000,
            // maxBorrowAmount_
            1000000000000,
            2e16,
            address(USDC)
        );

        jusd.transfer(address(jusdBank), 100000e6);

        swapContract = new SupportsSWAP(
            address(USDC),
            address(ETH),
            address(jojoOracleETH)
        );
        address[] memory swapContractList = new address[](1);
        swapContractList[0] = address(swapContract);
        uint256[] memory amountList = new uint256[](1);
        amountList[0] = 10000e6;
        USDC.mint(swapContractList, amountList);
        IERC20(jusd).transfer(address(jusdExchange), 5000e6);

        jusdBank.initReserve(
            // token
            address(ETH),
            // maxCurrencyBorrowRate
            8e17,
            // maxDepositAmount
            20300e18,
            // maxDepositAmountPerAccount
            2030e18,
            // maxBorrowValue
            100000e18,
            // liquidateMortgageRate
            825e15,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(jojoOracleETH)
        );
    }

    // all liquidate

    function testLiquidateAll() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            9000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liq = jusdBank.liquidate(
            alice,
            address(ETH),
            bob,
            10e18,
            afterParam,
            900e6
        );

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(ETH), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(ETH), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(USDC).balanceOf(alice);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);
        console.log((((aliceUsedBorrowed * 1e18) / 855000000) * 1e18) / 9e17);
        console.log((((aliceUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liq.actualCollateral, 9650428473034437946);
        assertEq(insuranceUSDC, 825111634);
        assertEq(aliceUSDC, 314614374);
        assertEq(bobUSDC, 434269282);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();
    }

    // liquidated is subaccount
    function testLiquidatedIsSubaccountAll() public {
        ETH.transfer(alice, 10e18);

        vm.startPrank(alice);
        address aliceSub = subaccountFactory.newSubaccount();
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000 deposit to aliceSub
        jusdBank.deposit(alice, address(ETH), 10e18, aliceSub);
        vm.warp(1000);

        bytes memory dataBorrow = jusdBank.getBorrowData(
            7426e6,
            aliceSub,
            false
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataBorrow, 0);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            9000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);
        // uint256 aliceSubUsedBorrowed = jusdBank.getBorrowBalance(aliceSub);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liq = jusdBank.liquidate(
            aliceSub,
            address(ETH),
            bob,
            10e18,
            afterParam,
            900e6
        );

        //judge
        // uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        // uint256 aliceSubBorrow = jusdBank.getBorrowBalance(aliceSub);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceSubUSDC = IERC20(USDC).balanceOf(aliceSub);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);
        // console.log((((aliceSubUsedBorrowed * 1e18) / 855000000) * 1e18) / 9e17);
        // console.log((((aliceSubUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        // console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        // console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        // assertEq(bobBorrow, 0);
        // assertEq(aliceSubBorrow, 0);
        assertEq(liq.actualCollateral, 9650428473034437946);
        assertEq(insuranceUSDC, 825111634);
        assertEq(aliceSubUSDC, 314614374);
        assertEq(bobUSDC, 434269282);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        // console.log("bob borrow", bobBorrow);
        // console.log("alice borrow", aliceSubBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceSubUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();

        vm.startPrank(alice);
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            alice,
            aliceSubUSDC
        );
        Subaccount(aliceSub).execute(address(USDC), transferData, 0);
        assertEq(IERC20(USDC).balanceOf(aliceSub), 0);
        assertEq(IERC20(USDC).balanceOf(alice), aliceSubUSDC);
    }

    function testLiquidateWhiteListOpen() public {
        ETH.transfer(alice, 10e18);
        bool isOpen = jusdBank.isLiquidatorWhitelistOpen();
        assertEq(isOpen, false);
        jusdBank.liquidatorWhitelistOpen();
        jusdBank.addLiquidator(bob);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            9000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liq = jusdBank.liquidate(
            alice,
            address(ETH),
            bob,
            10e18,
            afterParam,
            900e6
        );

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(ETH), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(ETH), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(USDC).balanceOf(alice);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);
        console.log((((aliceUsedBorrowed * 1e18) / 855000000) * 1e18) / 9e17);
        console.log((((aliceUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liq.actualCollateral, 9650428473034437946);
        assertEq(insuranceUSDC, 825111634);
        assertEq(aliceUSDC, 314614374);
        assertEq(bobUSDC, 434269282);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();
    }

    function testLiquidatePart() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        // flashLoanLiquidate.setOracle(address(ETH), address(jojoOracle900));

        bytes memory data = swapContract.getSwapData(5e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            4500e6,
            data
        );

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liq = jusdBank.liquidate(
            alice,
            address(ETH),
            bob,
            5e18,
            afterParam,
            900e6
        );

        assertEq(jusdBank.isAccountSafe(alice), true);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(ETH), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(ETH), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(USDC).balanceOf(alice);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);
        console.log((((5e18 * 855000000) / 1e18) * 9e17) / 1e18);
        // console.log((aliceUsedBorrowed * 1e17 / 1e18)* 1e18 / 9e17);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 5e18);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, aliceUsedBorrowed - 3847500000);
        assertEq(liq.actualCollateral, 5e18);
        assertEq(insuranceUSDC, 427500000);
        assertEq(aliceUSDC, 0);
        assertEq(bobUSDC, 225000000);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();
    }

    /// @notice user borrow jusd account is not safe
    function testHandleDebt() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);

        MockChainLink500 eth500 = new MockChainLink500();
        JOJOOracleAdaptor jojoOracle500 = new JOJOOracleAdaptor(
            address(eth500),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle500));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle500));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            5000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liq = jusdBank.liquidate(
            alice,
            address(ETH),
            bob,
            10e18,
            afterParam,
            900e6
        );

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(ETH), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(ETH), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(USDC).balanceOf(alice);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);
        uint256 insuranceBorrow = jusdBank.getBorrowBalance(insurance);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, aliceUsedBorrowed - 4275e6);
        assertEq(liq.actualCollateral, 10e18);
        assertEq(insuranceUSDC, 475000000);
        assertEq(aliceUSDC, 0);
        assertEq(bobUSDC, 250000000);
        assertEq(insuranceBorrow, 0);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        console.log("insurance borrow", insuranceBorrow);
        vm.stopPrank();
        address[] memory liquidaters = new address[](1);
        liquidaters[0] = alice;
        jusdBank.handleDebt(liquidaters);
    }

    function testRepayAmountNotEnough() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        LiquidateCollateralRepayNotEnough flashLoanLiquidate = new LiquidateCollateralRepayNotEnough(
                address(jusdBank),
                address(jusdExchange),
                address(USDC),
                address(jusd),
                insurance
            );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            data
        );

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        cheats.expectRevert("REPAY_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(ETH), bob, 10e18, afterParam, 900e6);
    }

    function testInsuranceAmountNotEnough() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        LiquidateCollateralInsuranceNotEnough flashLoanLiquidate = new LiquidateCollateralInsuranceNotEnough(
                address(jusdBank),
                address(jusdExchange),
                address(USDC),
                address(jusd),
                insurance
            );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            data
        );

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        cheats.expectRevert("INSURANCE_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(ETH), bob, 10e18, afterParam, 900e6);
    }

    function testLiquidatedAmountNotEnough() public {
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        LiquidateCollateralLiquidatedNotEnough flashLoanLiquidate = new LiquidateCollateralLiquidatedNotEnough(
                address(jusdBank),
                address(jusdExchange),
                address(USDC),
                address(jusd),
                insurance
            );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            data
        );

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        cheats.expectRevert("LIQUIDATED_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(ETH), bob, 10e18, afterParam, 900e6);
    }

    function testFlashloanLiquidateRevert() public {
        ETH.transfer(alice, 20e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 20e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 20e18, alice);
        vm.warp(1000);
        jusdBank.borrow(14860e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(20e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            18000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);

        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        cheats.expectRevert("ERC20: transfer amount exceeds balance");
        jusdBank.liquidate(alice, address(ETH), bob, 20e18, afterParam, 900e6);
        vm.stopPrank();
    }

    function testLiquidateOperatorNotInWhiteList() public {
        // liquidator is in the whiteliste but operator is not
        ETH.transfer(alice, 10e18);
        bool isOpen = jusdBank.isLiquidatorWhitelistOpen();
        assertEq(isOpen, false);
        jusdBank.liquidatorWhitelistOpen();
        jusdBank.addLiquidator(bob);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD = 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        MockChainLink900 eth900 = new MockChainLink900();
        JOJOOracleAdaptor jojoOracle900 = new JOJOOracleAdaptor(
            address(eth900),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        jusdBank.updateOracle(address(ETH), address(jojoOracle900));
        swapContract.addTokenPrice(address(ETH), address(jojoOracle900));

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            9000e6,
            data
        );

        // liquidate

        vm.startPrank(bob);
        jusdBank.setOperator(jim, true);
        vm.stopPrank();
        vm.startPrank(jim);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        DataTypes.LiquidateData memory liqBefore = jusdBank.liquidate(
            alice,
            address(ETH),
            bob,
            10e18,
            afterParam,
            900e6
        );

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(ETH), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(ETH), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(USDC).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(USDC).balanceOf(alice);
        uint256 bobUSDC = IERC20(USDC).balanceOf(bob);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liqBefore.actualCollateral, 9650428473034437946);
        assertEq(insuranceUSDC, 825111634);
        assertEq(aliceUSDC, 314614374);
        assertEq(bobUSDC, 434269282);
        vm.stopPrank();

        jusdBank.removeLiquidator(bob);
        jusdBank.addLiquidator(jim);
        vm.startPrank(jim);
        cheats.expectRevert("LIQUIDATOR_NOT_IN_THE_WHITELIST");
        jusdBank.liquidate(alice, address(ETH), bob, 10e18, afterParam, 900e6);
    }

    function testLiquidateNotOperator() public {
        // liquidator is in the whiteliste but operator is not
        ETH.transfer(alice, 10e18);
        vm.startPrank(alice);
        ETH.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(ETH), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        //init flashloanRepay
        jusd.mint(50000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50000e6);
        FlashLoanLiquidate flashLoanLiquidate = new FlashLoanLiquidate(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd),
            insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapData(10e18, address(ETH));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            address(bob),
            data
        );

        // liquidate
        vm.startPrank(jim);
        bytes memory afterParam = abi.encode(
            address(flashLoanLiquidate),
            param
        );
        cheats.expectRevert("CAN_NOT_OPERATE_ACCOUNT");
        jusdBank.liquidate(alice, address(ETH), bob, 10e18, afterParam, 900e6);
        vm.stopPrank();
    }
}
