// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IGauge} from "velodrome-finance/contracts/interfaces/IGauge.sol";
import {IPool} from "velodrome-finance/contracts/interfaces/IPool.sol";
import {IRouter} from "velodrome-finance/contracts/interfaces/IRouter.sol";
import {IVoter} from "velodrome-finance/contracts/interfaces/IVoter.sol";

import {Tranche} from "../src/Tranche.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {TestHelpers} from "./utils/TestHelpers.sol";

contract TrancheTest is Test, TestHelpers {
    Tranche private tranche;
    Vault private vault;
    uint256 private vaultDeposit;
    uint256 private takerDeposit;
    uint256 private liquidity;

    function setUp() public {
        VaultFactory factory = new VaultFactory(basisPointFee);
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
        tranche = getTranche();
    }

    function testRevertWhen_MaturityIsInvalid() public {
        vm.expectRevert(Tranche.InvalidMaturity.selector);
        new Tranche(block.timestamp, address(42));
    }

    function test_ConstructorBuildsTranche() public {
        uint256 maturityTimestamp = block.timestamp + DEFAULT_MATURITY;
        Tranche _tranche = new Tranche(maturityTimestamp, TAKER);
        assertEq(_tranche.maturityTimestamp(), maturityTimestamp);
        assertEq(_tranche.taker(), TAKER);
        assertEq(_tranche.vault(), address(this));
    }

    function testRevertWhen_MakerTriesToRemoveLiquidityBeforeMaturity() public {
        vm.expectRevert(Tranche.MaturityNotReached.selector);
        vm.prank(MAKER);
        tranche.withdrawTokens();
    }

    function test_MakerWithdrawsTokens() public {
        uint256 vaultMakerBalance = ERC20(MAKER_TOKEN).balanceOf(address(vault));
        uint256 takerBalance = ERC20(TAKER_TOKEN).balanceOf(TAKER);
        assertEq(IGauge(vault.gauge()).balanceOf(address(tranche)), liquidity);
        vm.warp(block.timestamp + 30 days);

        vm.prank(MAKER);
        (uint256 makerWithdrawal, uint256 takerWithdrawal) = tranche.withdrawTokens();

        assertEq(ERC20(MAKER_TOKEN).balanceOf(address(vault)), vaultMakerBalance + makerWithdrawal);
        assertEq(ERC20(TAKER_TOKEN).balanceOf(tranche.taker()), takerBalance + takerWithdrawal);
        assertEq(IGauge(vault.gauge()).balanceOf(address(tranche)), 0);
        assertEq(ERC20(MAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(ERC20(TAKER_TOKEN).balanceOf(address(tranche)), 0);
    }

    function testRevertWhen_NonInvestorWithdrawsRewards() public {
        vm.expectRevert(Tranche.Unauthorized.selector);
        vm.prank(address(403));
        tranche.withdrawRewards();
    }

    function test_MakerWithdrawsRewards() public {
        address vaultFactoryOwner = VaultFactory(vault.vaultFactory()).owner();
        address rewardToken = vault.rewardToken();
        assertEq(ERC20(rewardToken).balanceOf(MAKER), 0);
        assertEq(ERC20(rewardToken).balanceOf(TAKER), 0);
        assertEq(ERC20(rewardToken).balanceOf(vaultFactoryOwner), 0);
        vm.warp(block.timestamp + 100 days);

        vm.prank(MAKER);
        (uint256 makerRewards, uint256 takerRewards, uint256 fees) = tranche.withdrawRewards();

        assertEq(makerRewards, ERC20(rewardToken).balanceOf(MAKER));
        assertEq(takerRewards, ERC20(rewardToken).balanceOf(TAKER));
        assertEq(ERC20(rewardToken).balanceOf(address(tranche)), 0);
        assertEq(ERC20(rewardToken).balanceOf(vaultFactoryOwner), fees);
    }

    function testRevertWhen_NonInvestorTriesEmergencyLiquidation() public {
        vm.expectRevert(Tranche.Unauthorized.selector);
        vm.prank(address(403));
        tranche.emergencyLiquidation();
    }

    function test_InvestorsCanLiquidateTokensInEmergencyBeforeMaturity() public {
        uint256 vaultMakerBalance = ERC20(MAKER_TOKEN).balanceOf(address(vault));
        uint256 takerBalance = ERC20(TAKER_TOKEN).balanceOf(TAKER);
        vm.prank(TAKER);
        (uint256 m, uint256 t) = tranche.emergencyLiquidation();
        assertEq(m, 0);
        assertEq(t, 0);
        vm.warp(block.timestamp + 15 days);
        assertLt(block.timestamp, tranche.maturityTimestamp());

        vm.prank(MAKER);
        (uint256 makerWithdrawal, uint256 takerWithdrawal) = tranche.emergencyLiquidation();

        assertEq(ERC20(MAKER_TOKEN).balanceOf(address(vault)), vaultMakerBalance + makerWithdrawal);
        assertEq(ERC20(TAKER_TOKEN).balanceOf(tranche.taker()), takerBalance + takerWithdrawal);
        assertEq(IGauge(vault.gauge()).balanceOf(address(tranche)), 0);
        assertEq(ERC20(MAKER_TOKEN).balanceOf(address(tranche)), 0);
        assertEq(ERC20(TAKER_TOKEN).balanceOf(address(tranche)), 0);
    }

    function getTranche() public returns (Tranche) {
        if (vault.getTranchesSize() == 0) {
            vm.startPrank(MAKER);
            deal(MAKER_TOKEN, MAKER, makerAmount, true);
            ERC20(MAKER_TOKEN).approve(address(vault), makerAmount);
            vault.depositTokens(makerAmount);
            vm.stopPrank();

            vm.startPrank(TAKER);
            deal(TAKER_TOKEN, TAKER, takerAmount, true);
            ERC20(TAKER_TOKEN).approve(vault.router(), takerAmount);
            (address _tranche, uint256 _vaultDeposit, uint256 _takerDeposit, uint256 _liquidity) =
                vault.createTranche(takerAmount);
            tranche = Tranche(_tranche);
            vaultDeposit = _vaultDeposit;
            takerDeposit = _takerDeposit;
            liquidity = _liquidity;
            vm.stopPrank();

            return tranche;
        }
        uint256 i = vault.getTranchesSize() - 1;
        address[] memory t = vault.tranches();
        return Tranche(t[i]);
    }
}
