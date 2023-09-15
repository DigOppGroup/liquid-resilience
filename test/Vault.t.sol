// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "velodrome-finance/contracts/interfaces/IGauge.sol";
import {IPool} from "velodrome-finance/contracts/interfaces/IPool.sol";

import {Tranche} from "../src/Tranche.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {TestHelpers} from "./utils/TestHelpers.sol";

contract VaultTest is Test, TestHelpers {
    VaultFactory private factory;
    Vault private vault;

    function setUp() public {
        factory = new VaultFactory(basisPointFee);
        vault = Vault(
            factory.createVault(
                MAKER,
                makerRevBasisPoints,
                MAKER_TOKEN,
                DEFAULT_MATURITY,
                ROUTER,
                slippageBasisPoints,
                STABLE,
                TAKER_TOKEN
            )
        );
    }

    function testRevertWhen_FeesAreTooLargeForVault() public {
        uint16 excessFees = vault.BPS() + 3;

        vm.expectRevert(abi.encodeWithSelector(VaultFactory.ExceedsMaxBPS.selector, excessFees, factory.BPS()));
        vault = new Vault(
            excessFees,
            MAKER,
            makerRevBasisPoints,
            MAKER_TOKEN,
            DEFAULT_MATURITY,
            ROUTER,
            slippageBasisPoints,
            STABLE,
            TAKER_TOKEN
        );
    }

    function testRevertWhen_MakerAddressIsZero() public {
        vm.expectRevert();
        vault = new Vault(
            basisPointFee,
            address(0),
            makerRevBasisPoints,
            MAKER_TOKEN,
            DEFAULT_MATURITY,
            ROUTER,
            slippageBasisPoints,
            STABLE,
            TAKER_TOKEN
        );
    }

    function testRevertWhen_MakerRevenueCutTooLarge() public {
        uint16 tooHighRevCut = vault.BPS() + 1;

        vm.expectRevert(abi.encodeWithSelector(VaultFactory.ExceedsMaxBPS.selector, tooHighRevCut, factory.BPS()));
        vault = new Vault(
            basisPointFee,
            MAKER,
            tooHighRevCut,
            MAKER_TOKEN,
            DEFAULT_MATURITY,
            ROUTER,
            slippageBasisPoints,
            STABLE,
            TAKER_TOKEN
        );
    }

    function testRevertWhen_MakerTokenAddressIsZero() public {
        vm.expectRevert();
        vault = new Vault(
            basisPointFee,
            MAKER,
            makerRevBasisPoints,
            address(0),
            DEFAULT_MATURITY,
            ROUTER,
            slippageBasisPoints,
            STABLE,
            TAKER_TOKEN
        );
    }

    function testRevertWhen_RouterAddressIsZero() public {
        vm.expectRevert();
        vault = new Vault(
            basisPointFee,
            MAKER,
            makerRevBasisPoints,
            MAKER_TOKEN,
            DEFAULT_MATURITY,
            address(0),
            slippageBasisPoints,
            STABLE,
            TAKER_TOKEN
        );
    }

    function testRevertWhen_TakerTokenAddressIsZero() public {
        vm.expectRevert();
        vault = new Vault(
            basisPointFee,
            MAKER,
            makerRevBasisPoints,
            MAKER_TOKEN,
            DEFAULT_MATURITY,
            ROUTER,
            slippageBasisPoints,
            STABLE,
            address(0)
        );
    }

    function test_ConstructorBuildsVault() public {
        assertEq(vault.feeBasisPoints(), basisPointFee);
        assertEq(vault.vaultFactory(), address(factory));
        assertEq(vault.maker(), MAKER);
        assertEq(vault.makerRevenueBasisPoints(), makerRevBasisPoints);
        assertEq(vault.makerToken(), MAKER_TOKEN);
        assertEq(vault.maturity(), DEFAULT_MATURITY);
        assertEq(vault.slippageBasisPoints(), slippageBasisPoints);
        assertEq(vault.takerToken(), TAKER_TOKEN);
        assertEq(vault.router(), ROUTER);
    }

    function testRevertWhen_MakerDoesntDepositIntoVault() public {
        address caller = address(403);
        vm.expectRevert(abi.encodeWithSelector(Vault.Unauthorized.selector, caller, MAKER));
        vm.prank(caller);
        vault.depositTokens(1000);
    }

    function testRevertWhen_ZeroTokensDepositedIntoVault() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientAmount.selector, 0));
        vm.prank(MAKER);
        vault.depositTokens(0);
    }

    function test_MakerCanDepositIntoVault(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 0 && _depositAmount <= makerAmount);
        deal(MAKER_TOKEN, vault.maker(), _depositAmount, true);
        vm.startPrank(vault.maker());
        IERC20(MAKER_TOKEN).approve(address(vault), _depositAmount);

        vault.depositTokens(_depositAmount);
        vm.stopPrank();

        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), _depositAmount);
    }

    function testRevertWhen_TakerAmountIsZero() public {
        vm.startPrank(vault.maker());
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientAmount.selector, 0));
        vault.createTranche(0);
        vm.stopPrank();
    }

    function test_TakerCreatesTranche() public {
        uint256 makerTokenPoolBal = IERC20(MAKER_TOKEN).balanceOf(vault.getPool());
        uint256 takerTokenPoolBal = IERC20(TAKER_TOKEN).balanceOf(vault.getPool());
        vm.startPrank(vault.maker());
        deal(MAKER_TOKEN, vault.maker(), makerAmount, true);
        IERC20(MAKER_TOKEN).approve(address(vault), makerAmount);
        vault.depositTokens(makerAmount);
        vm.stopPrank();

        vm.startPrank(TAKER);
        deal(TAKER_TOKEN, TAKER, takerAmount, true);
        IERC20(TAKER_TOKEN).approve(address(vault), takerAmount);
        (address tranche, uint256 makerDeposit, uint256 takerDeposit, uint256 liquidity) =
            vault.createTranche(takerAmount);
        Tranche t = Tranche(tranche);
        vm.stopPrank();

        assertEq(t.taker(), TAKER);
        assertEq(t.maturityTimestamp(), block.timestamp + DEFAULT_MATURITY);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), makerAmount - makerDeposit);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(address(vault)), 0);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(TAKER), takerAmount - takerDeposit);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(vault.getPool()), makerTokenPoolBal + makerDeposit);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(vault.getPool()), takerTokenPoolBal + takerDeposit);
        assertGt(liquidity, 0);
        assertEq(IGauge(t.getGauge()).balanceOf(address(tranche)), liquidity);
    }

    function test_TakerCreatesTrancheAfterPreviousDisablingOfVault() public {
        uint256 makerTokenPoolBal = IERC20(MAKER_TOKEN).balanceOf(vault.getPool());
        uint256 takerTokenPoolBal = IERC20(TAKER_TOKEN).balanceOf(vault.getPool());
        vm.startPrank(vault.maker());
        deal(MAKER_TOKEN, vault.maker(), makerAmount, true);
        IERC20(MAKER_TOKEN).approve(address(vault), makerAmount);
        vault.depositTokens(makerAmount);
        vault.disableTrancheCreation();
        vault.enableTrancheCreation();
        vm.stopPrank();

        vm.startPrank(TAKER);
        deal(TAKER_TOKEN, TAKER, takerAmount, true);
        IERC20(TAKER_TOKEN).approve(address(vault), takerAmount);
        (address tranche, uint256 makerDeposit, uint256 takerDeposit, uint256 liquidity) =
            vault.createTranche(takerAmount);
        Tranche t = Tranche(tranche);
        vm.stopPrank();

        assertEq(t.taker(), TAKER);
        assertEq(t.maturityTimestamp(), block.timestamp + DEFAULT_MATURITY);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), makerAmount - makerDeposit);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(address(vault)), 0);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(TAKER), takerAmount - takerDeposit);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(vault.getPool()), makerTokenPoolBal + makerDeposit);
        assertEq(IERC20(TAKER_TOKEN).balanceOf(vault.getPool()), takerTokenPoolBal + takerDeposit);
        assertGt(liquidity, 0);
        assertEq(IGauge(t.getGauge()).balanceOf(address(tranche)), liquidity);
    }

    function testRevertWhen_NonMakerTriesToWithdrawFromVault() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.Unauthorized.selector, TAKER, MAKER));
        vm.prank(TAKER);
        vault.makerWithdrawTokensFromVault(1);
    }

    function testRevertWhen_WithdrawAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientAmount.selector, 0));
        vm.prank(MAKER);
        vault.makerWithdrawTokensFromVault(0);
    }

    function testRevertWhen_WithdrawAmountExceedsBalance() public {
        uint256 requestAmount = makerAmount + 1;
        deal(MAKER_TOKEN, address(vault), makerAmount, true);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, requestAmount, makerAmount));
        vm.prank(MAKER);
        vault.makerWithdrawTokensFromVault(makerAmount + 1);
    }

    function test_MakerCanWithdrawAllTokensFromVault() public {
        deal(MAKER_TOKEN, address(vault), makerAmount, true);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(MAKER), 0);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), makerAmount);

        vm.prank(MAKER);
        vault.makerWithdrawTokensFromVault(makerAmount);

        assertEq(IERC20(MAKER_TOKEN).balanceOf(MAKER), makerAmount);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), 0);
    }

    function test_MakerCanWithdrawSomeTokensFromVault() public {
        deal(MAKER_TOKEN, address(vault), makerAmount, true);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(MAKER), 0);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), makerAmount);
        uint256 withdrawalAmount = 1000;

        vm.prank(MAKER);
        vault.makerWithdrawTokensFromVault(withdrawalAmount);

        assertEq(IERC20(MAKER_TOKEN).balanceOf(MAKER), withdrawalAmount);
        assertEq(IERC20(MAKER_TOKEN).balanceOf(address(vault)), makerAmount - withdrawalAmount);
    }

    function test_GetTranchesSize() public {
        assertEq(vault.getTranchesSize(), 0);
        buildTestTranche();
        assertEq(vault.getTranchesSize(), 1);
    }

    function testRevertWhen_NonMakerTriesToEnableTrancheCreation() public {
        address caller = address(403);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Vault.Unauthorized.selector, caller, MAKER));
        vault.enableTrancheCreation();
    }

    function testRevertWhen_NonMakerTriesToDisableTrancheCreation() public {
        address caller = address(403);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Vault.Unauthorized.selector, caller, MAKER));
        vault.enableTrancheCreation();
    }

    function test_MakerCanEnableTrancheCreation() public {
        vm.startPrank(MAKER);
        vault.disableTrancheCreation();
        assertFalse(vault.trancheCreationEnabled());

        vault.enableTrancheCreation();
        vm.stopPrank();

        assertTrue(vault.trancheCreationEnabled());
    }

    function test_MakerCanDisableTrancheCreation() public {
        assertTrue(vault.trancheCreationEnabled());
        vm.prank(MAKER);
        vault.disableTrancheCreation();

        assertFalse(vault.trancheCreationEnabled());
    }

    function testRevertWhen_TrancheCreationIsDisabledAndTakerTriesToCreateTranche() public {
        vm.prank(MAKER);
        vault.disableTrancheCreation();
        deal(TAKER_TOKEN, TAKER, takerAmount, true);
        vm.startPrank(TAKER);
        IERC20(TAKER_TOKEN).approve(address(vault), takerAmount);

        vm.expectRevert(Vault.TrancheCreationDisabled.selector);
        vault.createTranche(takerAmount);
        vm.stopPrank();
    }

    function buildTestTranche() private {
        vm.startPrank(vault.maker());
        deal(MAKER_TOKEN, vault.maker(), makerAmount, true);
        IERC20(MAKER_TOKEN).approve(address(vault), makerAmount);
        vault.depositTokens(makerAmount);
        vm.stopPrank();

        vm.startPrank(TAKER);
        deal(TAKER_TOKEN, TAKER, takerAmount, true);
        IERC20(TAKER_TOKEN).approve(address(vault), takerAmount);
        vault.createTranche(takerAmount);
        vm.stopPrank();
    }
}
