// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputer} from "../src/IRecomputer.sol";
import {MockRecomputer} from "./mocks/MockRecomputer.sol";

/// @title GasModelCalibration — mediciones REPRODUCIBLES que justifican las
///        constantes del modelo de gas de DissentCore.
///
/// COMO CORRER (Foundry 1.8.1, con `network = "monad"` en foundry.toml):
///
///     forge test --match-contract GasModelCalibrationTest -vv
///
/// No impone cifras exactas (solo asserts laxos > 0); imprime los numeros que
/// respaldan cada constante. Las cifras dependen del perfil de gas de Monad, por
/// eso el `network = "monad"` es obligatorio.
///
/// QUE CONSTANTE RESPALDA CADA MEDICION:
///   - K_ENCODE_NUM (2.43/byte)   <- test_cal_encode
///   - K_SEAL_NUM   (2.62/byte)   <- test_cal_computeSeal
///   - K_INPUTS_NUM (0.19/byte)   <- test_cal_keccak_inputs
///   - C_CALL       (22k)         <- test_cal_staticcall_overhead
///        (mide STATICCALL frio ~18.6k / caliente ~10.4k en el perfil Monad. La
///         1ra llamada del reveal, validate, accede en FRIO; C_CALL=22k cubre ese
///         costo medido + ~14% de margen.)
///
/// DOS RESERVAS INDEPENDIENTES en _deliver(limit) = limit + ceil(limit/63) + C_CALL:
///   - ceil(limit/63) cubre EXCLUSIVAMENTE la regla EIP-150 (el 1/64 retenido por
///     el que llama). No esta disponible para el callee.
///   - C_CALL cubre EXCLUSIVAMENTE el overhead medido de la propia llamada (acceso
///     a cuenta, base del STATICCALL). No compensa EIP-150.
/// Los probes de AdapterFault.t.sol confirman end-to-end que validate y recompute
/// reciben V y R (menos ~560 de overhead de entrada del callee).
///   - revert de validate/recompute (camino fault) <- test_cal_revert
///   - CHALLENGE_COMMIT_GAS       <- test_cal_challengeCommit
///
/// ENTRY_OVERHEAD, PREWORK_RESERVE y SETTLE_RESERVE son ENVOLVENTES conservadoras,
/// no puntos exactos. ENTRY_OVERHEAD (entrada de challengeReveal hasta el chequeo
/// del piso) se midio con un build instrumentado; para reproducirlo, agregar al
/// principio de challengeReveal `uint256 __g0 = gasleft();` y, justo despues del
/// `SealMismatch`, `dbgPrecheck = __g0 - gasleft();` con `uint256 public dbgPrecheck;`,
/// correr un reveal y leer dbgPrecheck (dio ~17.5k hasta SealMismatch; +SSTORE de
/// settled). El efecto NETO de estas envolventes lo valida end-to-end
/// AdapterFault.t.sol: los probes muestran que el adaptador recibe R y V completos
/// (menos ~560 de overhead de entrada del callee), o sea el piso alcanza.
contract MinimalAdapter {
    bool immutable doRevert;

    constructor(bool r) {
        doRevert = r;
    }

    fallback() external {
        if (doRevert) revert("x");
        assembly {
            mstore(0, 42)
            return(0, 0x20) // int256 canonico
        }
    }
}

contract GasModelCalibrationTest is Test {
    DissentCore core;
    MockRecomputer mock;
    MinimalAdapter mAdapter;
    MinimalAdapter mReverter;
    address agent = makeAddr("agent");

    function setUp() public {
        core = new DissentCore();
        mock = new MockRecomputer();
        // creados en setUp (tx previa) para que el primer staticcall del test sea
        // FRIO de verdad; si se crean en el mismo test, el CREATE calienta la dir.
        mAdapter = new MinimalAdapter(false);
        mReverter = new MinimalAdapter(true);
        vm.deal(agent, 100 ether);
    }

    function _perByte(uint256 gAt, uint256 nAt, uint256 gBase, uint256 nBase) internal pure returns (uint256 milli) {
        // (gAt-gBase)/(nAt-nBase) en milesimas de gas/byte
        return ((gAt - gBase) * 1000) / (nAt - nBase);
    }

    function test_cal_encode() public view {
        uint256[3] memory ns = [uint256(32), 1024, 65536];
        uint256[3] memory gs;
        for (uint256 i = 0; i < 3; i++) {
            bytes memory a = new bytes(ns[i]);
            bytes memory b = new bytes(ns[i]);
            uint256 g0 = gasleft();
            bytes memory d = abi.encodeWithSelector(IRecomputer.recompute.selector, a, b);
            gs[i] = g0 - gasleft();
            require(d.length > 0, "x");
            console.log("encode n=%s (args ~2n): %s gas", ns[i], gs[i]);
        }
        // por byte de (inputs+evidence): denom = 2*(n - n0)
        console.log("K_ENCODE ~ %s milli-gas/byte", _perByte(gs[2], 2 * 65536, gs[0], 2 * 32));
        assertGt(gs[2], gs[0]);
    }

    function test_cal_keccak_inputs() public view {
        uint256[2] memory ns = [uint256(32), 65536];
        uint256[2] memory gs;
        for (uint256 i = 0; i < 2; i++) {
            bytes memory a = new bytes(ns[i]);
            uint256 g0 = gasleft();
            bytes32 h = keccak256(a);
            gs[i] = g0 - gasleft();
            require(h != bytes32(uint256(1)), "x");
        }
        console.log("keccak(inputs) n=32: %s ; n=65536: %s", gs[0], gs[1]);
        console.log("K_INPUTS ~ %s milli-gas/byte", _perByte(gs[1], 65536, gs[0], 32));
        assertGt(gs[1], gs[0]);
    }

    function test_cal_computeSeal() public view {
        uint256[2] memory ns = [uint256(32), 65536];
        uint256[2] memory gs;
        for (uint256 i = 0; i < 2; i++) {
            bytes memory e = new bytes(ns[i]);
            uint256 g0 = gasleft();
            bytes32 h = keccak256(abi.encode(e, bytes32("s"), address(this)));
            gs[i] = g0 - gasleft();
            require(h != bytes32(uint256(1)), "x");
        }
        console.log("computeSeal(evidence) n=32: %s ; n=65536: %s", gs[0], gs[1]);
        console.log("K_SEAL ~ %s milli-gas/byte", _perByte(gs[1], 65536, gs[0], 32));
        assertGt(gs[1], gs[0]);
    }

    function test_cal_staticcall_overhead() public {
        
        bytes memory data = abi.encodeWithSelector(IRecomputer.recompute.selector, abi.encode(int256(1)), abi.encode(int256(0)));
        // primer acceso: frio
        uint256 g0 = gasleft();
        (bool ok,) = address(mAdapter).staticcall(data);
        uint256 gc = g0 - gasleft();
        // segundo: caliente
        g0 = gasleft();
        (bool ok2,) = address(mAdapter).staticcall(data);
        uint256 gw = g0 - gasleft();
        console.log("C_CALL staticcall(32B->32B) frio=%s caliente=%s", gc, gw);
        assertTrue(ok && ok2);
    }

    function test_cal_revert() public {
        
        bytes memory data = abi.encodeWithSelector(IRecomputer.recompute.selector, abi.encode(int256(1)), abi.encode(int256(0)));
        uint256 g0 = gasleft();
        (bool ok,) = address(mReverter).staticcall(data);
        console.log("staticcall a adaptador que revierte: %s gas (ok=%s)", g0 - gasleft(), ok);
        assertFalse(ok);
    }

    function test_cal_challengeCommit() public {
        // gas EN-CONTRATO de challengeCommit (sin intrinseco de tx; el harness de
        // GasBudget lo suma aparte para llegar a ~150k). CHALLENGE_COMMIT_GAS=200k
        // cubre ese total + margen.
        vm.prank(agent, agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(mock), abi.encode(int256(200)), 100, DissentCore.Comparator.AtLeast, "c",
            0.1 ether, 1 hours, 1_000_000, 300_000, 64, bytes32(0)
        );
        bytes32 sealed_ = keccak256(abi.encode(abi.encode(int256(50)), bytes32("s"), agent));
        vm.prank(agent, agent);
        uint256 g0 = gasleft();
        core.challengeCommit{value: 0.1 ether}(id, sealed_);
        console.log("challengeCommit EN-CONTRATO: %s gas (+ intrinseco de tx aparte)", g0 - gasleft());
    }
}
