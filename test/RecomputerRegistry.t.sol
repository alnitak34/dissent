// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {RecomputerRegistry} from "../src/RecomputerRegistry.sol";
import {IRecomputerRegistry} from "../src/IRecomputerRegistry.sol";
import {MockRecomputer} from "./mocks/MockRecomputer.sol";

contract RecomputerRegistryTest is Test {
    RecomputerRegistry registry;
    DissentCore core;
    MockRecomputer recomputer;

    address agent = makeAddr("agent");
    address challenger = makeAddr("challenger");
    address outsider = makeAddr("outsider");
    address nextCurator = makeAddr("next-curator");

    uint128 constant DEPOSIT = 0.1 ether;
    uint32 constant RGL = 1_000_000;
    uint32 constant VGL = 200_000;
    uint32 constant MEL = 64;

    function setUp() public {
        registry = new RecomputerRegistry(address(this));
        core = new DissentCore(address(registry));
        recomputer = new MockRecomputer();
        vm.deal(agent, 10 ether);
        vm.deal(challenger, 10 ether);
    }

    function _register() internal returns (bytes32) {
        return registry.registerPolicy(address(recomputer), DEPOSIT, RGL, VGL, MEL);
    }

    function _commit(bytes32 policyId) internal returns (bytes32 id) {
        vm.prank(agent);
        id = core.commit{value: 1 ether}(
            policyId,
            abi.encode(int256(200)),
            100,
            DissentCore.Comparator.AtLeast,
            "registered policy",
            1 hours,
            bytes32(0)
        );
    }

    function test_registro_fija_todos_los_parametros() public {
        bytes32 policyId = _register();
        IRecomputerRegistry.Policy memory policy = registry.getPolicy(policyId);
        assertEq(policy.recomputer, address(recomputer));
        assertEq(policy.codeHash, address(recomputer).codehash);
        assertEq(policy.challengeDeposit, DEPOSIT);
        assertEq(policy.recomputeGasLimit, RGL);
        assertEq(policy.validateGasLimit, VGL);
        assertEq(policy.maxEvidenceLen, MEL);
        assertTrue(policy.active);

        DissentCore.Commitment memory commitment = core.getCommitment(_commit(policyId));
        assertEq(commitment.policyId, policyId);
        assertEq(commitment.recomputer, address(recomputer));
        assertEq(commitment.recomputerCodeHash, policy.codeHash);
        assertEq(commitment.deposit, DEPOSIT);
        assertEq(commitment.recomputeGasLimit, RGL);
        assertEq(commitment.validateGasLimit, VGL);
        assertEq(commitment.maxEvidenceLen, MEL);
    }

    function test_solo_curator_registra_y_cambia_estado() public {
        vm.prank(outsider);
        vm.expectRevert(RecomputerRegistry.NotCurator.selector);
        registry.registerPolicy(address(recomputer), DEPOSIT, RGL, VGL, MEL);

        bytes32 policyId = _register();
        vm.prank(outsider);
        vm.expectRevert(RecomputerRegistry.NotCurator.selector);
        registry.setPolicyActive(policyId, false);
    }

    function test_politica_no_se_puede_sobrescribir() public {
        bytes32 policyId = _register();
        vm.expectRevert(abi.encodeWithSelector(RecomputerRegistry.PolicyAlreadyExists.selector, policyId));
        registry.registerPolicy(address(recomputer), DEPOSIT, RGL, VGL, MEL);
    }

    function test_politica_desactivada_bloquea_solo_commits_nuevos() public {
        bytes32 policyId = _register();
        bytes32 commitmentId = _commit(policyId);
        registry.setPolicyActive(policyId, false);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.PolicyNotActive.selector, policyId));
        core.commit{value: 1 ether}(
            policyId,
            abi.encode(int256(200)),
            100,
            DissentCore.Comparator.AtLeast,
            "new commitment",
            1 hours,
            bytes32("new")
        );

        bytes memory evidence = abi.encode(int256(50));
        bytes32 salt = bytes32("challenge");
        vm.prank(challenger);
        core.challengeCommit{value: DEPOSIT}(commitmentId, keccak256(abi.encode(evidence, salt, challenger)));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal(commitmentId, abi.encode(int256(200)), evidence, salt);
        assertEq(uint8(core.getCommitment(commitmentId).status), uint8(DissentCore.Status.Challenged));
    }

    function test_policy_desconocida_no_crea_commitment() public {
        bytes32 unknown = keccak256("unknown");
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.PolicyNotActive.selector, unknown));
        core.commit{value: 1 ether}(
            unknown, abi.encode(int256(200)), 100, DissentCore.Comparator.AtLeast, "unknown", 1 hours, bytes32(0)
        );
    }

    function test_cambio_de_codehash_bloquea_commit() public {
        bytes32 policyId = _register();
        bytes32 expected = address(recomputer).codehash;
        vm.etch(address(recomputer), hex"00");
        bytes32 actual = address(recomputer).codehash;
        assertTrue(actual != expected);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.RecomputerCodeChanged.selector, expected, actual));
        core.commit{value: 1 ether}(
            policyId, abi.encode(int256(200)), 100, DissentCore.Comparator.AtLeast, "changed code", 1 hours, bytes32(0)
        );
    }

    function test_cambio_de_codehash_despues_del_commit_es_fault_sin_bounty() public {
        bytes32 commitmentId = _commit(_register());
        bytes memory evidence = abi.encode(int256(50));
        bytes32 salt = bytes32("changed-after-commit");

        vm.prank(challenger);
        core.challengeCommit{value: DEPOSIT}(commitmentId, keccak256(abi.encode(evidence, salt, challenger)));
        vm.etch(address(recomputer), hex"00");
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());

        vm.prank(challenger);
        core.challengeReveal(commitmentId, abi.encode(int256(200)), evidence, salt);

        assertEq(uint8(core.getCommitment(commitmentId).status), uint8(DissentCore.Status.Faulted));
        assertEq(core.credits(challenger), DEPOSIT, "retador recupera solo el deposito");
        assertEq(core.credits(agent), 1 ether, "recompensa vuelve al agente");
        assertEq(core.escrowed(), 0);
    }

    function test_deposito_del_challenge_sale_de_la_politica() public {
        bytes32 commitmentId = _commit(_register());
        vm.prank(challenger);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.BadValue.selector, DEPOSIT - 1, DEPOSIT));
        core.challengeCommit{value: DEPOSIT - 1}(commitmentId, bytes32("seal"));
    }

    function test_transferencia_de_curator_requiere_dos_pasos() public {
        registry.proposeCurator(nextCurator);
        assertEq(registry.pendingCurator(), nextCurator);

        vm.prank(outsider);
        vm.expectRevert(RecomputerRegistry.NotPendingCurator.selector);
        registry.acceptCurator();

        vm.prank(nextCurator);
        registry.acceptCurator();
        assertEq(registry.curator(), nextCurator);
        assertEq(registry.pendingCurator(), address(0));

        vm.expectRevert(RecomputerRegistry.NotCurator.selector);
        registry.registerPolicy(address(recomputer), DEPOSIT, RGL, VGL, MEL);
    }

    function test_rechaza_configuraciones_invalidas() public {
        vm.expectRevert(RecomputerRegistry.ZeroAddress.selector);
        registry.registerPolicy(address(0), DEPOSIT, RGL, VGL, MEL);

        vm.expectRevert(abi.encodeWithSelector(RecomputerRegistry.NotContract.selector, outsider));
        registry.registerPolicy(outsider, DEPOSIT, RGL, VGL, MEL);

        vm.expectRevert(RecomputerRegistry.ZeroDeposit.selector);
        registry.registerPolicy(address(recomputer), 0, RGL, VGL, MEL);

        vm.expectRevert(RecomputerRegistry.ZeroGasLimit.selector);
        registry.registerPolicy(address(recomputer), DEPOSIT, 0, VGL, MEL);

        uint32 maximum = registry.MAX_EVIDENCE_LEN();
        uint32 tooLarge = maximum + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                RecomputerRegistry.EvidenceLimitTooLarge.selector, uint256(tooLarge), uint256(maximum)
            )
        );
        registry.registerPolicy(address(recomputer), DEPOSIT, RGL, VGL, tooLarge);
    }

    function test_core_rechaza_registro_invalido() public {
        vm.expectRevert(abi.encodeWithSelector(DissentCore.InvalidRegistry.selector, address(0)));
        new DissentCore(address(0));

        vm.expectRevert(abi.encodeWithSelector(DissentCore.InvalidRegistry.selector, outsider));
        new DissentCore(outsider);
    }
}
