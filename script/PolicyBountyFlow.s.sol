// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ILegacyDissentCore} from "./interfaces/ILegacyDissentCore.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";

/// @notice Fases separadas para probar Policy Bounty sobre el despliegue
///         endurecido de Monad Testnet. Cada contrato produce como maximo una
///         transaccion. DISSENT_CHALLENGER_SALT nunca vive en el repo.
abstract contract PolicyBountyBase is Script {
    uint256 internal constant MONAD_TESTNET_CHAIN_ID = 10143;

    address internal constant CORE = 0x460f9F624da9e23c705c610E1263bf3641bCce23;
    address internal constant RECOMPUTER = 0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d;
    address internal constant AGENT = 0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A;
    address internal constant CHALLENGER = 0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02;

    uint256 internal constant REWARD = 3 ether;
    uint128 internal constant DEPOSIT = 0.1 ether;
    uint64 internal constant WINDOW = 1 days;
    uint32 internal constant RECOMPUTE_GAS_LIMIT = 20_000_000;
    uint32 internal constant VALIDATE_GAS_LIMIT = 100_000;
    uint32 internal constant MAX_EVIDENCE_LEN = 160;
    int256 internal constant THRESHOLD = 0;
    string internal constant ACTION = "Alnitak River Safety Reference v1";

    bytes32 internal constant POLICY_HASH = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0;
    bytes20 internal constant ORIGIN = hex"e6a7e49857602ac84257dc78f0960506f87cd7f3";

    function _requireDeployment() internal view {
        require(block.chainid == MONAD_TESTNET_CHAIN_ID, "solo Monad testnet 10143");
        require(CORE.code.length != 0, "DissentCore endurecido no desplegado");
        require(RECOMPUTER.code.length != 0, "Policy Bounty recomputer no desplegado");

        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(RECOMPUTER);
        require(recomputer.POLICY_SPEC_HASH() == POLICY_HASH, "policy hash inesperado");
        require(recomputer.ORIGIN_COMMIT() == ORIGIN, "origin commit inesperado");
        require(recomputer.MARGIN_BP() == 1500, "margin inesperado");
        require(recomputer.scale() == 1, "scale inesperado");
        require(recomputer.domain() == bytes32("alnitak.river.safety.v1"), "domain inesperado");
    }

    function _requireBroadcastSender(address expected) internal view {
        (, address sender,) = vm.readCallers();
        require(sender == expected, "cuenta de firma incorrecta");
    }

    function _inputs() internal pure returns (bytes memory) {
        return AlnitakPolicyBountyRecomputer(RECOMPUTER).canonicalInputs();
    }

    function _evidence() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"030f000000000000",
                traceLength: 2
            })
        );
    }

    function _requireCommitment(ILegacyDissentCore.Commitment memory commitment, bytes memory inputs) internal pure {
        require(commitment.status == ILegacyDissentCore.Status.Open, "commitment no esta Open");
        require(commitment.agent == AGENT, "agent inesperado");
        require(commitment.recomputer == RECOMPUTER, "recomputer inesperado");
        require(commitment.inputsHash == keccak256(inputs), "inputs inesperados");
        require(commitment.threshold == THRESHOLD, "threshold inesperado");
        require(commitment.comparator == ILegacyDissentCore.Comparator.AtMost, "comparator inesperado");
        require(commitment.reward == REWARD, "reward inesperada");
        require(commitment.deposit == DEPOSIT, "deposit inesperado");
        require(commitment.recomputeGasLimit == RECOMPUTE_GAS_LIMIT, "R inesperado");
        require(commitment.validateGasLimit == VALIDATE_GAS_LIMIT, "V inesperado");
        require(commitment.maxEvidenceLen == MAX_EVIDENCE_LEN, "max evidence inesperado");
        require(commitment.actionHash == keccak256(bytes(ACTION)), "action inesperada");
    }
}

contract PolicyBountyCommit is PolicyBountyBase {
    function run() external returns (bytes32 id) {
        _requireDeployment();
        ILegacyDissentCore core = ILegacyDissentCore(CORE);
        bytes memory inputs = _inputs();
        bytes32 agentSalt = vm.envBytes32("DISSENT_AGENT_SALT");
        require(agentSalt != bytes32(0), "agent salt vacio");

        uint256 txGas = core.txRequired(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        uint256 minimum =
            core.minGasBackedReward(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        require(txGas <= core.MONAD_TX_GAS_LIMIT(), "reveal no entra en 30M");
        require(REWARD >= minimum, "3 MON ya no cubren el minimo onchain");

        vm.startBroadcast();
        _requireBroadcastSender(AGENT);
        id = core.commit{value: REWARD}(
            RECOMPUTER,
            inputs,
            THRESHOLD,
            ILegacyDissentCore.Comparator.AtMost,
            ACTION,
            DEPOSIT,
            WINDOW,
            RECOMPUTE_GAS_LIMIT,
            VALIDATE_GAS_LIMIT,
            MAX_EVIDENCE_LEN,
            agentSalt
        );
        vm.stopBroadcast();

        console.log("txRequired del reveal", txGas);
        console.log("minGasBackedReward", minimum);
        console.log("commitment id (el evento onchain es la autoridad):");
        console.logBytes32(id);
    }
}

contract PolicyBountyChallengeCommit is PolicyBountyBase {
    function run() external returns (bytes32 sealedHash) {
        _requireDeployment();
        ILegacyDissentCore core = ILegacyDissentCore(CORE);
        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(RECOMPUTER);
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 challengerSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(challengerSalt != bytes32(0), "challenger salt vacio");

        bytes memory inputs = _inputs();
        bytes memory evidence = _evidence();
        _requireCommitment(core.getCommitment(id), inputs);
        (bool valid, bytes32 reason) = recomputer.validateEvidence(inputs, evidence);
        require(valid && reason == bytes32(0), "contraejemplo rechazado");
        require(recomputer.recompute(inputs, evidence) == 1, "JhJd no produce violacion");

        sealedHash = core.computeSeal(evidence, challengerSalt, CHALLENGER);
        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.stopBroadcast();

        console.log("sealedHash:");
        console.logBytes32(sealedHash);
    }
}

contract PolicyBountyChallengeReveal is PolicyBountyBase {
    function run() external {
        _requireDeployment();
        ILegacyDissentCore core = ILegacyDissentCore(CORE);
        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(RECOMPUTER);
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 challengerSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(challengerSalt != bytes32(0), "challenger salt vacio");

        bytes memory inputs = _inputs();
        bytes memory evidence = _evidence();
        _requireCommitment(core.getCommitment(id), inputs);

        bytes32 expectedSeal = core.computeSeal(evidence, challengerSalt, CHALLENGER);
        (bytes32 storedSeal, uint64 sealBlock,, bool settled) = core.seals(id, CHALLENGER);
        require(storedSeal == expectedSeal, "salt/evidencia no corresponden al sello");
        require(sealBlock != 0 && !settled, "sello ausente o liquidado");
        require(block.number >= sealBlock + core.REVEAL_DELAY_BLOCKS(), "todavia es temprano");
        require(
            block.number <= sealBlock + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS(),
            "ventana de reveal vencida"
        );
        (bool valid,) = recomputer.validateEvidence(inputs, evidence);
        require(valid, "contraejemplo rechazado");
        require(recomputer.recompute(inputs, evidence) == 1, "evidencia no refuta");

        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.challengeReveal(id, inputs, evidence, challengerSalt);
        vm.stopBroadcast();
    }
}

contract PolicyBountyWithdraw is PolicyBountyBase {
    function run() external {
        _requireDeployment();
        ILegacyDissentCore core = ILegacyDissentCore(CORE);
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        ILegacyDissentCore.Commitment memory commitment = core.getCommitment(id);
        require(commitment.status == ILegacyDissentCore.Status.Challenged, "commitment no fue refutado");
        require(core.credits(CHALLENGER) == REWARD + DEPOSIT, "credito challenger inesperado");

        vm.startBroadcast();
        _requireBroadcastSender(CHALLENGER);
        core.withdrawCredit();
        vm.stopBroadcast();
    }
}
