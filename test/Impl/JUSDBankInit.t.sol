// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "ds-test/test.sol";

import "../../src/Impl/JUSDBank.sol";
import "../../src/Impl/JUSDExchange.sol";
import "@JOJO/contracts/testSupport/TestERC20.sol";
import "../mocks/MockERC20.sol";
import "@JOJO/contracts/testSupport/TestERC20.sol";
import "../../src/token/JUSD.sol";
import "../../src/oracle/JOJOOracleAdaptor.sol";
import "../mocks/MockChainLink.t.sol";
import "../mocks/MockChainLink2.sol";
import "../../src/Testsupport/SupportsSWAP.sol";
import "../mocks/MockChainLink500.sol";
import "../mocks/MockJOJODealer.sol";
import "../mocks/MockUSDCPrice.sol";
import "../mocks/MockChainLinkBadDebt.sol";
import "../../src/lib/DataTypes.sol";
import {Utils} from "../utils/Utils.sol";
import "../../src/Impl/flashloanImpl/GeneralRepay.sol";
import "forge-std/Test.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

contract JUSDBankInitTest is Test {
    Cheats internal constant cheats =
        Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    uint256 public constant ONE = 1e18;

    Utils internal utils;
    address deployAddress;

    JUSDBank public jusdBank;
    TestERC20 public mockToken2;

    MockERC20 public mockToken1;
    JUSDExchange public jusdExchange;

    JUSD public jusd;
    JOJOOracleAdaptor public jojoOracle1;
    JOJOOracleAdaptor public jojoOracle2;
    MockChainLink public mockToken1ChainLink;
    MockChainLink2 public mockToken2ChainLink;
    MockUSDCPrice public usdcPrice;
    MockJOJODealer public jojoDealer;
    SupportsSWAP public swapContract;
    TestERC20 public USDC;
    GeneralRepay public generalRepay;
    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal insurance;
    address internal jim;

    function setUp() public {
        mockToken2 = new TestERC20("BTC", "BTC", 8);

        address[] memory user = new address[](1);
        user[0] = address(address(this));
        uint256[] memory amountForMockToken2 = new uint256[](1);
        amountForMockToken2[0] = 4000e8;
        mockToken2.mint(user, amountForMockToken2);

        mockToken1 = new MockERC20(5000e18);

        jusd = new JUSD(6);
        mockToken1ChainLink = new MockChainLink();
        mockToken2ChainLink = new MockChainLink2();
        usdcPrice = new MockUSDCPrice();
        jojoDealer = new MockJOJODealer();
        jojoOracle1 = new JOJOOracleAdaptor(
            address(mockToken1ChainLink),
            20,
            86400,
            address(usdcPrice)
        );
        jojoOracle2 = new JOJOOracleAdaptor(
            address(mockToken2ChainLink),
            10,
            86400,
            address(usdcPrice)
        );
        // mock users
        utils = new Utils();
        users = utils.createUsers(5);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        insurance = users[2];
        vm.label(insurance, "Insurance");
        jim = users[3];
        vm.label(jim, "Jim");
        jusd.mint(200000e6);
        jusd.mint(100000e6);
        USDC = new TestERC20("USDC", "USDC", 6);
        // initial
        jusdBank = new JUSDBank( // maxReservesAmount_
            10,
            insurance,
            address(jusd),
            address(jojoDealer),
            // maxBorrowAmountPerAccount_
            100000000000,
            // maxBorrowAmount_
            100000000001,
            // borrowFeeRate_
            2e16,
            address(USDC)
        );
        deployAddress = jusdBank.owner();

        jusd.transfer(address(jusdBank), 200000e6);
        //  mockToken2 BTC mockToken1 ETH
        jusdBank.initReserve(
            // token
            address(mockToken2),
            // initialMortgageRate
            7e17,
            // maxDepositAmount
            300e8,
            // maxDepositAmountPerAccount
            210e8,
            // maxBorrowValue
            100000e6,
            // liquidateMortgageRate
            8e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(jojoOracle2)
        );

        jusdBank.initReserve(
            // token
            address(mockToken1),
            // initialMortgageRate
            8e17,
            // maxDepositAmount
            4000e18,
            // maxDepositAmountPerAccount
            2030e18,
            // maxBorrowValue
            100000e6,
            // liquidateMortgageRate
            825e15,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(jojoOracle1)
        );

        swapContract = new SupportsSWAP(
            address(USDC),
            address(mockToken1),
            address(jojoOracle1)
        );
        address[] memory swapContractList = new address[](1);
        swapContractList[0] = address(swapContract);
        uint256[] memory amountList = new uint256[](1);
        amountList[0] = 100000e6;
        USDC.mint(swapContractList, amountList);

        jusdExchange = new JUSDExchange(address(USDC), address(jusd));
        jusd.transfer(address(jusdExchange), 100000e6);

        generalRepay = new GeneralRepay(
            address(jusdBank),
            address(jusdExchange),
            address(USDC),
            address(jusd)
        );
    }

    function testOwner() public {
        assertEq(deployAddress, jusdBank.owner());
    }

    function testInitMint() public {
        assertEq(jusd.balanceOf(address(jusdBank)), 200000e6);
    }

    function testRefundJUSDBank() public {
        jusdBank.refundJUSD(100000e6);
        assertEq(jusd.balanceOf(address(jusdBank)), 100000e6);
    }

    function testRefundJUSDExechange() public {
        jusdExchange.refundJUSD(50000e6);
        assertEq(jusd.balanceOf(address(jusdExchange)), 50000e6);
    }
}
