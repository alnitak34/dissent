// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputer} from "../src/IRecomputer.sol";

/// @notice Prueba de referencia EIP-1153. Vive fuera de test/ para no cambiar
///         el target EVM del build normal. CI la copia temporalmente a test/ y
///         la ejecuta con --evm-version cancun.
contract TransientReadRecomputer is IRecomputer {
    // Slot arbitrario y fijo de esta prueba. Debe ser literal porque Solidity
    // solo admite constantes numericas directas como operandos de tstore/tload
    // dentro de inline assembly.
    uint256 private constant SLOT = 0xD155E17;

    function arm(int256 value) external {
        assembly {
            tstore(SLOT, value)
        }
    }

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "transient.read";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256 value) {
        int256 base = abi.decode(inputs, (int256));
        if (evidence.length == 0) return base;
        assembly {
            value := tload(SLOT)
        }
        return value == 0 ? base : value;
    }
}

/// @notice ABI compatible con IRecomputer, pero recompute no es view porque
///         intenta TSTORE. Dissent lo invoca con STATICCALL de bajo nivel.
contract TransientWriteRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "transient.write";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external returns (int256) {
        int256 base = abi.decode(inputs, (int256));
        if (evidence.length == 0) return base;
        assembly {
            tstore(0, 1)
        }
        return 50;
    }
}

/// @notice Hace TSTORE y reveal en la misma transaccion. Como el sello esta
///         ligado a msg.sender, este contrato tambien debe ser quien selle.
contract SameTransactionChallenger {
    DissentCore private immutable core;

    constructor(DissentCore c) {
        core = c;
    }

    function seal(bytes32 id, bytes32 sealedHash) external payable {
        core.challengeCommit{value: msg.value}(id, sealedHash);
    }

    function armAndReveal(
        TransientReadRecomputer recomputer,
        int256 transientValue,
        bytes32 id,
        bytes calldata inputs,
        bytes calldata evidence,
        bytes32 salt
    ) external {
        recomputer.arm(transientValue);
        core.challengeReveal(id, inputs, evidence, salt);
    }

    function reveal(bytes32 id, bytes calldata inputs, bytes calldata evidence, bytes32 salt) external {
        core.challengeReveal(id, inputs, evidence, salt);
    }
}

contract TransientStorageBoundaryTest is Test {
    DissentCore private core;
    address private agent = makeAddr("agent");
    address private alice = makeAddr("alice");

    uint128 private constant REWARD = 1 ether;
    uint128 private constant DEPOSIT = 0.1 ether;
    int256 private constant BASE = 200;
    int256 private constant THRESHOLD = 100;
    uint32 private constant RGL = 1_000_000;
    uint32 private constant VGL = 200_000;
    uint32 private constant MEL = 64;

    function setUp() public {
        core = new DissentCore();
        vm.deal(address(this), 100 ether);
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
    }

    function _commit(address recomputer, bytes32 salt) private returns (bytes32 id) {
        vm.prank(agent, agent);
        id = core.commit{value: REWARD}(
            recomputer,
            abi.encode(BASE),
            THRESHOLD,
            DissentCore.Comparator.AtLeast,
            "call",
            DEPOSIT,
            1 hours,
            RGL,
            VGL,
            MEL,
            salt
        );
    }

    function _seal(bytes memory evidence, bytes32 salt, address who) private pure returns (bytes32) {
        return keccak256(abi.encode(evidence, salt, who));
    }

    /// @dev EIP-1153: TSTORE dentro de STATICCALL es una excepcion. La politica
    ///      segura lo clasifica Faulted, devuelve ambos principales y no paga bounty.
    function test_tstore_durante_staticcall_es_fault_sin_bounty() public {
        TransientWriteRecomputer rc = new TransientWriteRecomputer();
        bytes32 id = _commit(address(rc), "write");
        bytes memory evidence = hex"01";

        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _seal(evidence, "ev", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), evidence, "ev");

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Faulted));
        assertEq(core.credits(alice), DEPOSIT, "solo vuelve el deposito");
        assertEq(core.credits(agent), REWARD, "la recompensa vuelve al agente");
    }

    /// @dev LIMITACION, no defensa: TLOAD esta permitido bajo STATICCALL. Un
    ///      adaptador que lee estado transitorio preparado por el retador puede
    ///      devolver un resultado ABI canonico distinto y obtener un payout real.
    ///      El nucleo no puede distinguirlo de una refutacion semantica valida.
    function test_tload_prearmado_puede_cambiar_resultado_canonico() public {
        TransientReadRecomputer rc = new TransientReadRecomputer();
        SameTransactionChallenger challenger = new SameTransactionChallenger(core);
        vm.deal(address(challenger), DEPOSIT);
        bytes32 id = _commit(address(rc), "read");
        bytes memory evidence = hex"01";
        bytes32 salt = "ev";

        challenger.seal{value: DEPOSIT}(id, _seal(evidence, salt, address(challenger)));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        challenger.armAndReveal(rc, 50, id, abi.encode(BASE), evidence, salt);

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
        assertEq(core.credits(address(challenger)), REWARD + DEPOSIT, "payout canonico condicionado por TLOAD");
        assertEq(core.credits(agent), 0);
    }

    /// @dev Control: sin TSTORE previo, el mismo adaptador devuelve BASE y el
    ///      challenge falla. Aisla el estado transitorio como unica diferencia.
    function test_sin_tstore_previo_el_mismo_adaptador_no_refuta() public {
        TransientReadRecomputer rc = new TransientReadRecomputer();
        SameTransactionChallenger challenger = new SameTransactionChallenger(core);
        vm.deal(address(challenger), DEPOSIT);
        bytes32 id = _commit(address(rc), "control");
        bytes memory evidence = hex"01";
        bytes32 salt = "ev";

        challenger.seal{value: DEPOSIT}(id, _seal(evidence, salt, address(challenger)));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        challenger.reveal(id, abi.encode(BASE), evidence, salt);

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertEq(core.credits(agent), DEPOSIT, "challenge normal fallido");
        assertEq(core.credits(address(challenger)), 0);
    }
}
