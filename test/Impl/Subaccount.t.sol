// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "ds-test/test.sol";
import "../../src/Impl/JUSDBank.sol";
import "../mocks/MockERC20.sol";
import "../../src/token/JUSD.sol";
import "../../src/oracle/JOJOOracleAdaptor.sol";
import "../mocks/MockChainLink.t.sol";
import "../mocks/MockJOJODealer.sol";
import "../../src/lib/DataTypes.sol";
import "@JOJO/contracts/subaccount/Subaccount.sol";
import "@JOJO/contracts/impl/JOJODealer.sol";
import "@JOJO/contracts/intf/IDealer.sol";
import "@JOJO/contracts/subaccount/SubaccountFactory.sol";
import "@JOJO/contracts/testSupport/TestERC20.sol";
import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/Impl/JUSDExchange.sol";
import "../../src/Impl/flashloanImpl/FlashLoanRepay.sol";
import "../../src/Testsupport/SupportsSWAP.sol";
import "../mocks/MockChainLinkBadDebt.sol";
import "../../src/lib/DecimalMath.sol";
import "../mocks/MockUSDCPrice.sol";
import "../mocks/MockDepositETH.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

contract SubaccountTest is Test {
    Cheats internal constant cheats =
        Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    using DecimalMath for uint256;

    JUSDBank public jusdBank;
    MockDepositETH public mockDepositETH;
    MockERC20 public mockToken1;
    TestERC20 public USDC;
    JUSD public jusd;
    JOJOOracleAdaptor public jojoOracle1;
    MockChainLink public mockToken1ChainLink;
    MockUSDCPrice public usdcPrice;
    JOJODealer public jojoDealer;
    SubaccountFactory public subaccountFactory;
    JUSDExchange jusdExchange;
    FlashLoanRepay public flashLoanRepay;
    SupportsSWAP public supportsSWAP;
    address internal alice = address(1);
    address internal bob = address(2);
    address internal insurance = address(3);

    function setUp() public {
        mockToken1 = new MockERC20(2000e18);
        jusd = new JUSD(6);
        USDC = new TestERC20("USDC", "USDC", 6);
        mockToken1ChainLink = new MockChainLink();
        usdcPrice = new MockUSDCPrice();
        jojoDealer = new JOJODealer(address(USDC));
        jojoOracle1 = new JOJOOracleAdaptor(
            address(mockToken1ChainLink),
            20,
            86400,
            address(usdcPrice),
            86400
        );
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(insurance, "Insurance");
        jusd.mint(200000e6);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        mockDepositETH = new MockDepositETH();
        subaccountFactory = new SubaccountFactory();
        jusdExchange = new JUSDExchange(address(USDC), address(jusd));
        jusd.transfer(address(jusdExchange), 100000e6);
        jusdBank = new JUSDBank( // maxReservesAmount_
            2,
            insurance,
            address(jusd),
            address(jojoDealer),
            // maxBorrowAmountPerAccount_
            6000e18,
            // maxBorrowAmount_
            9000e18,
            // borrowFeeRate_
            2e16,
            address(USDC)
        );

        jusd.transfer(address(jusdBank), 100000e6);
        flashLoanRepay = new FlashLoanRepay(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd)
        );
        supportsSWAP = new SupportsSWAP(
            address(USDC),
            address(mockToken1),
            address(jojoOracle1)
        );

        flashLoanRepay.setWhiteListContract(address(supportsSWAP), true);
        jusdBank.initReserve(
            // token
            address(mockToken1),
            // maxCurrencyBorrowRate
            5e17,
            // maxDepositAmount
            180e18,
            // maxDepositAmountPerAccount
            100e18,
            // maxBorrowValue
            100000e18,
            // liquidateMortgageRate
            9e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e16,
            address(jojoOracle1)
        );
    }

    function getSetOperatorData(
        address op,
        bool isValid
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature("setOperator(address,bool) ", op, isValid);
    }

    function testOperatorJOJOSubaccount() public {
        mockToken1.transfer(alice, 10e18);
        address[] memory user = new address[](2);
        user[0] = alice;
        user[1] = address(supportsSWAP);
        uint256[] memory amount = new uint256[](2);
        amount[0] = 1000e6;
        amount[1] = 100000e6;
        USDC.mint(user, amount);
        vm.startPrank(alice);
        mockToken1.approve(address(jusdBank), 10e18);
        address aliceSub = subaccountFactory.newSubaccount();
        bytes memory data = jojoDealer.getSetOperatorCallData(alice, true);
        Subaccount(aliceSub).execute(address(jojoDealer), data, 0);
        // alice is the operator of aliceSub in JOJODealer system and can operate the sub account.
        assertEq(IDealer(jojoDealer).isOperatorValid(aliceSub, alice), true);

        // aliceSub is the operator of alice in JUSD system and can operate alice
        // so that aliceSub can control alice to deposit collateral to subaccount
        // deposit can be devided into two situation:
        // 1. main account can deposit directly into sub account.
        jusdBank.deposit(alice, address(mockToken1), 1e18, aliceSub);
        // 2. multicall deposit and borrow, in this situation,
        // users need to let aliceSub operate main account, and borrow from subaccount
        jusdBank.setOperator(aliceSub, true);
        bytes memory dataDeposit = jusdBank.getDepositData(
            alice,
            address(mockToken1),
            1e18,
            aliceSub
        );
        bytes memory dataBorrow = jusdBank.getBorrowData(
            500e6,
            aliceSub,
            false
        );
        bytes[] memory multiCallData = new bytes[](2);
        multiCallData[0] = dataDeposit;
        multiCallData[1] = dataBorrow;
        bytes memory excuteData = abi.encodeWithSignature(
            "multiCall(bytes[])",
            multiCallData
        );
        Subaccount(aliceSub).execute(address(jusdBank), excuteData, 0);
        console.log(
            "aliceSub deposit",
            jusdBank.getDepositBalance(address(mockToken1), aliceSub)
        );
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));
        console.log("alice borrow", jusdBank.getBorrowBalance(alice));

        bytes memory dataWithdraw = jusdBank.getWithdrawData(
            address(mockToken1),
            5e17,
            alice,
            false
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataWithdraw, 0);
        console.log(
            "aliceSub deposit",
            jusdBank.getDepositBalance(address(mockToken1), aliceSub)
        );

        // flashloan situation
        // subaccount call flashloan and repay to it's own account
        bytes memory swapParam = abi.encodeWithSignature(
            "swap(uint256,address)",
            2e17,
            address(mockToken1)
        );
        bytes memory param = abi.encode(
            address(supportsSWAP),
            address(supportsSWAP),
            200e6,
            swapParam
        );
        bytes memory dataFlashloan = abi.encodeWithSignature(
            "flashLoan(address,address,uint256,address,bytes)",
            address(flashLoanRepay),
            address(mockToken1),
            2e17,
            aliceSub,
            param
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataFlashloan, 0);
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));

        // main account call flashloan function repay to other account
        jusdBank.deposit(alice, address(mockToken1), 1e18, alice);
        swapParam = abi.encodeWithSignature(
            "swap(uint256,address)",
            3e17,
            address(mockToken1)
        );
        param = abi.encode(
            address(supportsSWAP),
            address(supportsSWAP),
            300e6,
            swapParam
        );
        jusdBank.flashLoan(
            address(flashLoanRepay),
            address(mockToken1),
            3e17,
            aliceSub,
            param
        );
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));

        assertEq(jusdBank.getBorrowBalance(aliceSub), 0);

//        bytes memory dataDepositETH = abi.encodeWithSignature("deposit()");
//        Subaccount(aliceSub).execute{value: 2 ether}(address(mockDepositETH), dataDepositETH, 1 ether);
//        uint256 balance = address(mockDepositETH).balance;
//        assertEq(balance, 1 ether);

        vm.stopPrank();

        vm.startPrank(bob);
        bytes memory dataBob = jojoDealer.getSetOperatorCallData(bob, true);
        cheats.expectRevert("Ownable: caller is not the owner");
        Subaccount(aliceSub).execute(address(jusdBank), dataBob, 0);
    }
}
