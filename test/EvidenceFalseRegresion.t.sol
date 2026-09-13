// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputer} from "../src/IRecomputer.sol";

/// @notice REGRESION DE SEGURIDAD — los cuatro ataques de validateEvidence, ahora
///         CERRADOS por la politica AdapterFault / ChallengeRejected.
///
/// validateEvidence puede completar y devolver ok=false de forma canonica segun
/// el contexto de ejecucion (tx.origin, block.number, gasleft o siempre false).
/// Antes eso hacia `revert EvidenceRejected`, el sello quedaba unsettled y
/// sweepExpiredSeal le entregaba el deposito al agente: el agente cosechaba.
///
/// Con la politica nueva, un ok=false canonico liquida el sello y DEVUELVE el
/// deposito al retador; el compromiso sigue Open; el agente no recibe nada. Estos
/// cuatro tests fijan ese comportamiento: en ningun caso el agente cosecha, y en
/// ningun caso el retador pierde el deposito por gas insuficiente (se le da gas
/// de sobra; validate corre CAPADO, asi que el truco de gasleft tampoco engaña).
contract EvidenceFalseVulnRecomputer is IRecomputer {
    enum Mode {
        Origin,
        BlockParity,
        GasLeft,
        AlwaysFalse
    }

    Mode public mode;
    address public immutable agent;
    uint256 public immutable gasThreshold;

    constructor(Mode m, address a, uint256 gt) {
        mode = m;
        agent = a;
        gasThreshold = gt;
    }

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "evidence-false.vuln";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external view returns (bool ok, bytes32) {
        if (evidence.length == 0) return (true, bytes32(0));
        if (mode == Mode.Origin) return (tx.origin == agent, bytes32("ONLY_AGENT"));
        if (mode == Mode.BlockParity) return (block.number % 2 == 0, bytes32("BLOCK_PARITY"));
        if (mode == Mode.GasLeft) return (gasleft() > gasThreshold, bytes32("GAS_DEP"));
        return (false, bytes32("ALWAYS_NO"));
    }

    function recompute(bytes calldata inputs, bytes calldata) external pure returns (int256) {
        return abi.decode(inputs, (int256));
    }
}

contract EvidenceFalseRegresionTest is Test {
    DissentCore core;
    address agent = makeAddr("agent");
    address alice = makeAddr("alice");

    uint128 constant REWARD = 1 ether;
    uint128 constant DEPOSIT = 0.1 ether;
    uint64 constant WINDOW = 1 hours;
    int256 constant BASE = 200;
    int256 constant THRESHOLD = 100;
    // validate CAPADO a 200k: dentro de validate gasleft <= ~200k, muy por debajo
    // del umbral de 1_000_000 del modo GasLeft, asi que devuelve false igual que en
    // la tx real. El cap no evita la mentira; la semantica de rechazo la vuelve
    // inofensiva (se devuelve el deposito).
    uint32 constant RGL = 1_000_000;
    uint32 constant VGL = 200_000;
    uint32 constant MEL = 64;

    function setUp() public {
        core = new DissentCore();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
    }

    function _sealOf(bytes memory ev, bytes32 salt, address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(ev, salt, who));
    }

    /// @dev Corre el flujo con gas de SOBRA (el retador financia bien) y devuelve
    ///      el id. La unica variable es la mentira del adaptador.
    function _flujo(EvidenceFalseVulnRecomputer.Mode m) internal returns (bytes32 id) {
        EvidenceFalseVulnRecomputer rc = new EvidenceFalseVulnRecomputer(m, agent, 1_000_000);
        vm.roll(100);

        vm.prank(agent, agent);
        id = core.commit{value: REWARD}(
            address(rc),
            abi.encode(BASE),
            THRESHOLD,
            DissentCore.Comparator.AtLeast,
            "call",
            DEPOSIT,
            WINDOW,
            RGL,
            VGL,
            MEL,
            bytes32(0)
        );

        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "sal", alice));
        uint256 selloEn = vm.getBlockNumber();

        vm.roll(selloEn + core.REVEAL_DELAY_BLOCKS()); // 105: impar
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), ev, "sal");
    }

    /// @dev En los cuatro modos: ChallengeRejected, deposito devuelto, Open, y el
    ///      sello settled hace que sweep no pueda pagarle al agente.
    function _afirmarProtegido(bytes32 id) internal {
        assertEq(core.credits(alice), DEPOSIT, "la retadora recupera el deposito");
        assertEq(core.credits(agent), 0, "el agente NO cosecha");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open), "sigue Open");
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
        vm.expectRevert(DissentCore.NoSeal.selector);
        core.sweepExpiredSeal(id, alice);
    }

    function test_a_origin_no_cosecha() public {
        _afirmarProtegido(_flujo(EvidenceFalseVulnRecomputer.Mode.Origin));
    }

    function test_b_block_number_no_cosecha() public {
        _afirmarProtegido(_flujo(EvidenceFalseVulnRecomputer.Mode.BlockParity));
    }

    function test_c_gasleft_no_cosecha() public {
        _afirmarProtegido(_flujo(EvidenceFalseVulnRecomputer.Mode.GasLeft));
    }

    function test_d_always_false_no_cosecha() public {
        _afirmarProtegido(_flujo(EvidenceFalseVulnRecomputer.Mode.AlwaysFalse));
    }
}
