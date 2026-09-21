// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ILegacyDissentCore} from "./interfaces/ILegacyDissentCore.sol";
import {FaultProbeRecomputer} from "./DeployFaultProbe.s.sol";

/// @notice Flujo de prueba para Monad Testnet. Cada fase transmite COMO MAXIMO
///         una transaccion, solo si se invoca con --broadcast. Los salts se
///         proporcionan por entorno y nunca aparecen en el repositorio.
abstract contract FaultProbeBase is Script {
    address internal constant CORE = 0x460f9F624da9e23c705c610E1263bf3641bCce23;
    address internal constant AGENT = 0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A;
    address internal constant CHALLENGER = 0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02;
    uint256 internal constant REWARD = 0.25 ether;
    uint128 internal constant DEPOSIT = 0.01 ether;
    uint32 internal constant R = 1_000_000;
    uint32 internal constant V = 100_000;
    uint32 internal constant MAX_EV = 32;

    function _core() internal view returns (ILegacyDissentCore core) {
        require(block.chainid == 10143, "solo Monad Testnet");
        require(CORE.code.length != 0, "core ausente");
        core = ILegacyDissentCore(CORE);
    }

    function _probe() internal view returns (FaultProbeRecomputer probe) {
        address addr = vm.envAddress("DISSENT_FAULT_PROBE_ADDRESS");
        require(addr.code.length != 0, "probe ausente");
        require(addr.codehash == keccak256(type(FaultProbeRecomputer).runtimeCode), "bytecode de probe incorrecto");
        probe = FaultProbeRecomputer(addr);
        require(probe.domain() == bytes32("dissent.fault.probe.v1"), "probe incorrecto");
        require(probe.scale() == 1, "escala incorrecta");
    }

    function _inputs() internal pure returns (bytes memory) {
        return abi.encode(int256(200));
    }

    function _evidence() internal pure returns (bytes memory) {
        return abi.encode(int256(50));
    }

    function _sender(address expected) internal view {
        (, address actual,) = vm.readCallers();
        require(actual == expected, "cuenta de firma incorrecta");
    }

    function _commitment(ILegacyDissentCore core, bytes32 id, FaultProbeRecomputer probe) internal view {
        ILegacyDissentCore.Commitment memory c = core.getCommitment(id);
        require(c.status == ILegacyDissentCore.Status.Open, "campana no abierta");
        require(c.agent == AGENT && c.recomputer == address(probe), "campana ajena");
        require(c.inputsHash == keccak256(_inputs()), "inputs ajenos");
        require(c.threshold == 100 && c.comparator == ILegacyDissentCore.Comparator.AtLeast, "regla ajena");
        require(c.actionHash == keccak256(bytes("FAULT_PROBE_TESTNET_ONLY")), "accion ajena");
        require(c.reward == REWARD && c.deposit == DEPOSIT, "importes ajenos");
        require(c.recomputeGasLimit == R && c.validateGasLimit == V && c.maxEvidenceLen == MAX_EV, "gas ajeno");
    }
}

contract FaultProbeCommit is FaultProbeBase {
    function run() external returns (bytes32 id) {
        ILegacyDissentCore core = _core();
        FaultProbeRecomputer probe = _probe();
        bytes32 salt = vm.envBytes32("DISSENT_FAULT_AGENT_SALT");
        require(salt != bytes32(0), "salt vacio");
        bytes memory inputs = _inputs();
        uint256 minReward = core.minGasBackedReward(V, R, inputs.length, MAX_EV);
        require(REWARD >= minReward, "reward no cubre el piso onchain");

        vm.startBroadcast();
        _sender(AGENT);
        id = core.commit{value: REWARD}(
            address(probe),
            inputs,
            100,
            ILegacyDissentCore.Comparator.AtLeast,
            "FAULT_PROBE_TESTNET_ONLY",
            DEPOSIT,
            1 hours,
            R,
            V,
            MAX_EV,
            salt
        );
        vm.stopBroadcast();
        console.log("minGasBackedReward", minReward);
        console.log("id simulado; el evento onchain es la autoridad:");
        console.logBytes32(id);
    }
}

contract FaultProbeSeal is FaultProbeBase {
    function run() external {
        ILegacyDissentCore core = _core();
        FaultProbeRecomputer probe = _probe();
        bytes32 id = vm.envBytes32("DISSENT_FAULT_COMMITMENT_ID");
        bytes32 salt = vm.envBytes32("DISSENT_FAULT_CHALLENGER_SALT");
        require(salt != bytes32(0), "salt vacio");
        _commitment(core, id, probe);
        bytes32 sealedHash = core.computeSeal(_evidence(), salt, CHALLENGER);

        vm.startBroadcast();
        _sender(CHALLENGER);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.stopBroadcast();
    }
}

contract FaultProbeReveal is FaultProbeBase {
    function run() external {
        ILegacyDissentCore core = _core();
        FaultProbeRecomputer probe = _probe();
        bytes32 id = vm.envBytes32("DISSENT_FAULT_COMMITMENT_ID");
        bytes32 salt = vm.envBytes32("DISSENT_FAULT_CHALLENGER_SALT");
        _commitment(core, id, probe);
        bytes memory evidence = _evidence();
        (bytes32 stored, uint64 atBlock,, bool settled) = core.seals(id, CHALLENGER);
        require(atBlock != 0 && !settled, "sello ausente/liquidado");
        require(stored == core.computeSeal(evidence, salt, CHALLENGER), "salt/evidencia no corresponden");
        require(block.number >= atBlock + core.REVEAL_DELAY_BLOCKS(), "reveal temprano");
        require(block.number <= atBlock + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS(), "reveal vencido");

        vm.startBroadcast();
        _sender(CHALLENGER);
        core.challengeReveal(id, _inputs(), evidence, salt);
        vm.stopBroadcast();
        require(core.getCommitment(id).status == ILegacyDissentCore.Status.Faulted, "no termino Faulted");
    }
}
