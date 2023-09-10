// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {TestHelpers} from "./utils/TestHelpers.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

contract VaultFactoryTest is Test, TestHelpers {
    event VaultCreated(address indexed maker, address indexed vaultAddress);

    VaultFactory private factory;

    function setUp() public {
        factory = new VaultFactory(basisPointFee);
    }

    function testRevertWhen_FeeBasisPointsExceedsMax() public {
        uint16 tooHighFee = factory.BPS() + 1;
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.ExceedsMaxBPS.selector, tooHighFee, factory.BPS()));
        new VaultFactory(tooHighFee);
    }

    function test_ConstructorBuildsFactory() public {
        assertEq(factory.owner(), address(this));
        assertEq(factory.basisPointFee(), basisPointFee);
    }

    function testRevertWhen_NonOwnerCallsCreateVault() public {
        address caller = address(403);
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.NotOwner.selector, caller, address(this)));
        vm.prank(caller);
        factory.createVault(MAKER, makerRevBasisPoints, MAKER_TOKEN, DEFAULT_MATURITY, ROUTER, STABLE, TAKER_TOKEN);
    }

    function test_FactoryCanBuildAVault() public {
        vm.expectEmit(true, false, false, false);
        emit VaultCreated(MAKER, address(0));
        address v =
            factory.createVault(MAKER, makerRevBasisPoints, MAKER_TOKEN, DEFAULT_MATURITY, ROUTER, STABLE, TAKER_TOKEN);

        assertEq(Vault(v).vaultFactory(), address(factory));
        assertEq(Vault(v).maker(), MAKER);
        assertEq(factory.getVaultsSize(), 1);
    }

    function testRevertWhen_NonOwnerTriesToChangeFees() public {
        address caller = address(403);
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.NotOwner.selector, caller, address(this)));
        vm.prank(caller);
        factory.setBasisPointFee(0);
    }

    function testRevertWhen_OwnerTriesToChangeFeesThatExceedsMaxBPS() public {
        uint16 tooHighFee = factory.BPS() + 1;
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.ExceedsMaxBPS.selector, tooHighFee, factory.BPS()));
        factory.setBasisPointFee(tooHighFee);
    }

    function test_FactoryOwnerCanChangeFeesForVaults(uint16 newBasisPointFee) public {
        vm.assume(newBasisPointFee <= factory.BPS());
        Vault v1 = Vault(
            factory.createVault(MAKER, makerRevBasisPoints, MAKER_TOKEN, DEFAULT_MATURITY, ROUTER, STABLE, TAKER_TOKEN)
        );

        factory.setBasisPointFee(newBasisPointFee);

        Vault v2 = Vault(
            factory.createVault(MAKER, makerRevBasisPoints, MAKER_TOKEN, DEFAULT_MATURITY, ROUTER, STABLE, TAKER_TOKEN)
        );

        assertEq(v1.feeBasisPoints(), basisPointFee);
        assertEq(v2.feeBasisPoints(), newBasisPointFee);
        assertEq(factory.getVaultsSize(), 2);
    }
}
