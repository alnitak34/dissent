// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";

/// @notice Operaciones separadas para la primera demostracion real de Dissent.
/// @dev Cada contrato produce una sola transaccion. Se simula primero y solo se
///      transmite despues con `--browser --broadcast`. El salt del challenger
///      NUNCA vive en el repo: entra por DISSENT_CHALLENGER_SALT.
abstract contract DemoBase is Script {
    uint256 internal constant MONAD_TESTNET_CHAIN_ID = 10143;

    address internal constant CORE = 0x6dCD184c9c0db42FCD0De731F9a2855b38916758;
    address internal constant RECOMPUTER = 0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38;
    address internal constant AGENT = 0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A;
    address internal constant CHALLENGER = 0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02;

    uint256 internal constant REWARD = 3 ether;
    uint128 internal constant DEPOSIT = 0.1 ether;
    uint64 internal constant WINDOW = 1 hours;
    uint32 internal constant RECOMPUTE_GAS_LIMIT = 20_000_000;
    uint32 internal constant VALIDATE_GAS_LIMIT = 100_000;
    uint32 internal constant MAX_EVIDENCE_LEN = 32;
    int256 internal constant THRESHOLD = 362900000000000000;
    bytes32 internal constant AGENT_SALT = 0x77ca50cb814cb7190a87af0ebcff9df2606d4995ff43845d20d24b97c35130b0;

    function _inputs() internal pure returns (bytes memory) {
        return hex"0000000000000000000000000000000000000000000000000000000000000031"
            hex"0000000000000000000000000000000000000000000000000000000000000039"
            hex"000000000000000000000000000000000000000000000000000000000000000b"
            hex"0000000000000000000000000000000000000000000000000000000000000008"
            hex"0000000000000000000000000000000000000000000000000000000000000028"
            hex"0000000000000000000000000000000000000000000000000000000000000030"
            hex"0000000000000000000000000000000000000000000000000000000000000025"
            hex"0000000000000000000000000000000000000000000000000000000000002026"
            hex"0000000000000000000000000000000000000000000000000000000000000ac8"
            hex"0000000000000000000000000000000000000000000000000000000000000672"
            hex"0000000000000000000000000000000000000000000000000000000000000e2d";
    }

    function _requireNetworkAndCode() internal view {
        require(block.chainid == MONAD_TESTNET_CHAIN_ID, "solo Monad testnet 10143");
        require(CORE.code.length != 0, "DissentCore no desplegado");
        require(RECOMPUTER.code.length != 0, "recomputer no desplegado");
    }

    function _requireBroadcastSender(address expected) internal view {
        (, address sender,) = vm.readCallers();
        require(sender == expected, "cuenta de firma incorrecta");
    }
}

contract DemoCommit is DemoBase {
    function run() external returns (bytes32 id) {
        _requireNetworkAndCode();
        DissentCore core = DissentCore(CORE);
        bytes memory inputs = _inputs();
        uint256 minimum =
            core.minGasBackedReward(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        require(REWARD >= minimum, "3 MON ya no cubren el minimo onchain");

        vm.startBroadcast();
        _requireBroadcastSender(AGENT);
        id = core.commit{value: REWARD}(
            RECOMPUTER,
            inputs,
            THRESHOLD,
            DissentCore.Comparator.AtLeast,
            "river call QdAd vs 2s 2c Tc Qc 9d @ cmtr0ktvzxa5q15he4ekev8ub#29",
            DEPOSIT,
            WINDOW,
            RECOMPUTE_GAS_LIMIT,
            VALIDATE_GAS_LIMIT,
            MAX_EVIDENCE_LEN,
            AGENT_SALT
        );
        vm.stopBroadcast();

        console.log("ID de la simulacion (el recibo onchain es la autoridad):");
        console.logBytes32(id);
    }
}

contract DemoChallengeCommit is DemoBase {
    function run() external returns (bytes32 sealedHash) {
        _requireNetworkAndCode();
        DissentCore core = DissentCore(CORE);
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 secretSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(secretSalt != bytes32(0), "salt secreto vacio");

        DissentCore.Commitment memory commitment = core.getCommitment(id);
        require(commitment.status == DissentCore.Status.Open, "commitment no esta Open");
        require(commitment.agent == AGENT, "agent inesperado");
        require(commitment.recomputer == RECOMPUTER, "recomputer inesperado");
        require(commitment.inputsHash == keccak256(_inputs()), "inputs inesperados");

        bytes memory evidence = abi.encode(uint256(2)); // OVERBET
        sealedHash = core.computeSeal(evidence, secretSalt, CHALLENGER);

        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.stopBroadcast();

        console.log("sealedHash:");
        console.logBytes32(sealedHash);
    }
}

contract DemoChallengeReveal is DemoBase {
    function run() external {
        _requireNetworkAndCode();
        DissentCore core = DissentCore(CORE);
        AlnitakRiverRecomputer recomputer = AlnitakRiverRecomputer(RECOMPUTER);
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 secretSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(secretSalt != bytes32(0), "salt secreto vacio");

        bytes memory inputs = _inputs();
        bytes memory evidence = abi.encode(uint256(2)); // OVERBET
        bytes32 expectedSeal = core.computeSeal(evidence, secretSalt, CHALLENGER);
        (bytes32 storedSeal, uint64 sealBlock,, bool settled) = core.seals(id, CHALLENGER);
        require(storedSeal == expectedSeal, "salt/evidencia no corresponden al sello");
        require(sealBlock != 0 && !settled, "sello ausente o ya liquidado");
        require(block.number >= sealBlock + core.REVEAL_DELAY_BLOCKS(), "todavia es temprano");
        require(
            block.number <= sealBlock + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS(),
            "ventana de reveal vencida"
        );

        (bool valid,) = recomputer.validateEvidence(inputs, evidence);
        require(valid, "evidencia rechazada por el adaptador");
        int256 newValue = recomputer.recompute(inputs, evidence);
        require(newValue < THRESHOLD, "esta evidencia no refuta el compromiso");

        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.challengeReveal(id, inputs, evidence, secretSalt);
        vm.stopBroadcast();
    }
}

contract DemoWithdraw is DemoBase {
    function run() external {
        _requireNetworkAndCode();
        DissentCore core = DissentCore(CORE);
        require(core.credits(CHALLENGER) != 0, "challenger sin credito");

        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.withdrawCredit();
        vm.stopBroadcast();
    }
}
