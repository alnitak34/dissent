// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";
import {DissentCore} from "../src/DissentCore.sol";

/// @title GasBudget — cada operacion de usuario contra el limite de 30M por tx
///
/// QUE VERIFICA
/// Escenarios concretos (cuatro manos x tres tiers, challenge exitoso y fallido,
/// reclaim y withdrawCredit) contra el limite de 30.000.000 de gas por
/// transaccion de Monad, usando la tabla de gas de FOUNDRY. Cada operacion corre
/// en su propia llamada con gas = 30.000.000 - intrinseco (21000 + calldata);
/// si no entra, esa llamada revierte y el test se cae.
///
/// QUE NO DEMUESTRA
/// - No demuestra el gas exacto en Monad: Foundry cobra los opcodes con la tabla
///   de Ethereum, y Monad no tiene por que coincidir.
/// - No demuestra el precio final: Monad cobra el gas LIMIT declarado, no el
///   usado, y el precio depende del base fee y la propina del momento.
/// - No demuestra el peor caso: son cuatro manos, no todas las posibles.
/// La validacion definitiva requiere eth_estimateGas y transacciones reales en
/// Monad testnet.
///
/// COMO LEE EL GAS
/// Reporta gas POR OPERACION, una linea por llamada y el maximo por operacion al
/// final. NUNCA suma varias operaciones del test como si fueran una sola
/// transaccion del usuario: el test entero gasta cientos de millones porque
/// encadena decenas de operaciones, y ese total no significa nada. Por lo mismo,
/// este archivo no se corre con --gas-limit 30000000 (eso limitaria la funcion de
/// test entera, no cada operacion). Para contar el acceso frio a storage como en
/// una transaccion suelta:
///
///     forge test --match-contract GasBudgetTest --isolate -vv
contract GasBudgetTest is Test {
    uint256 constant TX_LIMIT = 30_000_000;
    bytes32 constant SAL = keccak256("sal");

    AlnitakRiverRecomputer rc;
    DissentCore core;
    address agent = makeAddr("agent");
    address alice = makeAddr("alice");

    string[6] ops = [
        "commit",
        "challengeCommit",
        "challengeReveal exitoso",
        "challengeReveal fallido",
        "reclaim",
        "withdrawCredit"
    ];
    mapping(bytes32 => uint256) maximo;
    mapping(bytes32 => string) dondeMaximo;

    function setUp() public {
        rc = new AlnitakRiverRecomputer();
        core = new DissentCore();
        vm.deal(agent, 1000 ether);
        vm.deal(alice, 1000 ether);
    }

    function _enc(uint8[2] memory hole, uint8[5] memory board, uint256[3] memory mix, uint256 price)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(AlnitakRiverRecomputer.Inputs({hole: hole, board: board, mixBp: mix, priceBp: price}));
    }

    /// @dev 21000 + 4 por byte cero + 16 por byte no cero.
    function _intrinseco(bytes memory data) internal pure returns (uint256 g) {
        g = 21_000;
        for (uint256 i = 0; i < data.length; i++) {
            g += data[i] == 0 ? 4 : 16;
        }
    }

    /// @dev Una operacion = una llamada con su propio presupuesto de 30M.
    function _medir(string memory op, string memory donde, address from, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        uint256 intr = _intrinseco(data);
        vm.prank(from);
        uint256 g0 = gasleft();
        (bool ok, bytes memory ret) = address(core).call{gas: TX_LIMIT - intr, value: value}(data);
        uint256 total = g0 - gasleft() + intr;
        if (!ok) {
            console.log("NO ENTRA EN 30M:", op, donde);
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        assertLe(total, TX_LIMIT, op);
        console.log(string.concat(op, " | ", donde), total);

        bytes32 k = keccak256(bytes(op));
        if (total > maximo[k]) {
            maximo[k] = total;
            dondeMaximo[k] = donde;
        }
        return ret;
    }

    function _flujo(bytes memory inp, string memory mano, uint256 tier, int256 umbral, bool exito) internal {
        string memory donde = string.concat(mano, ", tier ", vm.toString(tier));
        bytes32 salt = keccak256(abi.encode(mano, tier, exito));
        bytes memory r = _medir(
            "commit",
            donde,
            agent,
            1 ether,
            abi.encodeCall(
                DissentCore.commit,
                (address(rc), inp, umbral, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, 20_000_000, 100_000, 32, salt)
            )
        );
        bytes32 id = abi.decode(r, (bytes32));

        bytes memory ev = abi.encode(tier);
        bytes32 sello = keccak256(abi.encode(ev, SAL, alice));
        _medir("challengeCommit", donde, alice, 0.1 ether, abi.encodeCall(DissentCore.challengeCommit, (id, sello)));
        // vm.getBlockNumber y no block.number: con via_ir el optimizador puede
        // releer block.number despues de un vm.roll.
        uint256 selloEn = vm.getBlockNumber();

        vm.roll(selloEn + core.REVEAL_DELAY_BLOCKS());
        _medir(
            exito ? "challengeReveal exitoso" : "challengeReveal fallido",
            donde,
            alice,
            0,
            abi.encodeCall(DissentCore.challengeReveal, (id, inp, ev, SAL))
        );
        assertEq(
            uint8(core.getCommitment(id).status),
            exito ? uint8(DissentCore.Status.Challenged) : uint8(DissentCore.Status.Open)
        );

        if (!exito) {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            vm.roll(selloEn + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
            _medir("reclaim", donde, alice, 0, abi.encodeCall(DissentCore.reclaim, (id)));
            assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Reclaimed));
        }
    }

    function test_cada_operacion_entra_en_30M() public {
        bytes[4] memory manos;
        string[4] memory nombres = ["spot A", "spot B", "spot C", "mano real"];
        // Las mismas manos que AlnitakRiverRecomputer.t.sol y ManoReal.t.sol.
        manos[0] = _enc([uint8(44), 48], [uint8(43), 52, 9, 27, 18], [uint256(7190), 1690, 750], 2156);
        manos[1] = _enc([uint8(47), 57], [uint8(58), 26, 50, 59, 24], [uint256(7190), 1690, 750], 2156);
        manos[2] = _enc([uint8(20), 57], [uint8(52), 48, 47, 43, 10], [uint256(9660), 6670, 3450], 2156);
        manos[3] = hex"0000000000000000000000000000000000000000000000000000000000000031"
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

        for (uint256 h = 0; h < 4; h++) {
            // Estas llamadas preparan umbrales; no se miden ni cuentan.
            int256 base = rc.recompute(manos[h], "");
            for (uint256 t = 0; t < 3; t++) {
                int256 v = rc.recompute(manos[h], abi.encode(t));
                // fallido: un umbral que el valor del tier tambien cumple
                _flujo(manos[h], nombres[h], t, v < base ? v : base, false);
                // exitoso: solo existe si el tier baja el valor
                if (v < base) _flujo(manos[h], nombres[h], t, v + 1, true);
            }
        }

        _medir("withdrawCredit", "alice", alice, 0, abi.encodeCall(DissentCore.withdrawCredit, ()));
        _medir("withdrawCredit", "agent", agent, 0, abi.encodeCall(DissentCore.withdrawCredit, ()));

        console.log("--- maximo por operacion (margen contra 30M) ---");
        for (uint256 i = 0; i < ops.length; i++) {
            bytes32 k = keccak256(bytes(ops[i]));
            assertGt(maximo[k], 0, ops[i]);
            console.log(string.concat(ops[i], " | ", dondeMaximo[k]), maximo[k], TX_LIMIT - maximo[k]);
        }
    }
}
