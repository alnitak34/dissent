// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputer} from "../src/IRecomputer.sol";

/// @notice Recomputer mínimo: el base viene de inputs y el challenge de evidence.
contract DepthHonestRecomputer is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "call.depth.reference";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external pure returns (bool, bytes32) {
        return (evidence.length == 32, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        return evidence.length == 0 ? abi.decode(inputs, (int256)) : abi.decode(evidence, (int256));
    }
}

/// @notice Challenger que conserva los argumentos en storage y desciende con
///         calldata mínima. Atrapa el primer fallo para poder informar cuántos
///         marcos se alcanzaron sin revertir toda la llamada exterior.
contract DepthChallenger {
    DissentCore private immutable core;
    bytes32 private commitmentId;
    bytes private inputs;
    bytes private evidence;
    bytes32 private salt;

    // 1 = reveal completó; 2 = reveal revirtió; 3 = una llamada recursiva falló.
    uint8 internal constant REVEAL_COMPLETED = 1;
    uint8 internal constant REVEAL_REVERTED = 2;
    uint8 internal constant CHILD_CALL_FAILED = 3;

    constructor(DissentCore c) {
        core = c;
    }

    function configureAndSeal(bytes32 id, bytes calldata in_, bytes calldata ev_, bytes32 salt_) external payable {
        commitmentId = id;
        inputs = in_;
        evidence = ev_;
        salt = salt_;
        bytes32 sealedHash = keccak256(abi.encode(ev_, salt_, address(this)));
        core.challengeCommit{value: msg.value}(id, sealedHash);
    }

    function descend(uint256 remaining) external returns (uint256 framesReached, uint8 terminal) {
        if (remaining == 0) {
            (bool ok,) = address(core).call(
                abi.encodeWithSelector(core.challengeReveal.selector, commitmentId, inputs, evidence, salt)
            );
            return (0, ok ? REVEAL_COMPLETED : REVEAL_REVERTED);
        }

        (bool childOk, bytes memory result) =
            address(this).call(abi.encodeWithSelector(this.descend.selector, remaining - 1));
        if (!childOk || result.length != 64) return (1, CHILD_CALL_FAILED);

        (uint256 childFrames, uint8 childTerminal) = abi.decode(result, (uint256, uint8));
        return (childFrames + 1, childTerminal);
    }
}

contract CallDepthBoundaryTest is Test {
    DissentCore private core;
    DepthHonestRecomputer private recomputer;
    address private agent = makeAddr("agent");

    uint128 private constant REWARD = 1 ether;
    uint128 private constant DEPOSIT = 0.1 ether;
    int256 private constant BASE = 200;
    int256 private constant COUNTEREXAMPLE = 50;
    int256 private constant THRESHOLD = 100;
    uint32 private constant RGL = 1_000_000;
    uint32 private constant VGL = 200_000;
    uint32 private constant MEL = 32;

    function setUp() public {
        core = new DissentCore();
        recomputer = new DepthHonestRecomputer();
        vm.deal(address(this), 100 ether);
        vm.deal(agent, 100 ether);
    }

    function _newCampaign(bytes32 campaignSalt) private returns (bytes32 id, DepthChallenger challenger) {
        vm.prank(agent, agent);
        id = core.commit{value: REWARD}(
            address(recomputer),
            abi.encode(BASE),
            THRESHOLD,
            DissentCore.Comparator.AtLeast,
            "call",
            DEPOSIT,
            1 hours,
            RGL,
            VGL,
            MEL,
            campaignSalt
        );

        challenger = new DepthChallenger(core);
        challenger.configureAndSeal{value: DEPOSIT}(id, abi.encode(BASE), abi.encode(COUNTEREXAMPLE), "ev");
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
    }

    function test_control_sin_profundidad_refuta() public {
        (bytes32 id, DepthChallenger challenger) = _newCampaign("control");
        (uint256 reached, uint8 terminal) = challenger.descend(0);

        assertEq(reached, 0);
        assertEq(terminal, 1, "el reveal de control debe completar");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
        assertEq(core.credits(address(challenger)), REWARD + DEPOSIT);
    }

    /// @notice Con una llamada exterior limitada a los 30M de Monad, se intenta
    ///         crear una cadena de 1024 marcos antes del reveal. EIP-150 o el piso
    ///         de gas deben detener el camino antes de una liquidación falsa.
    function test_1024_marcos_con_30M_no_producen_fault_ni_pago() public {
        (bytes32 id, DepthChallenger challenger) = _newCampaign("deep");

        (bool outerOk, bytes memory result) =
            address(challenger).call{gas: core.MONAD_TX_GAS_LIMIT()}(abi.encodeWithSelector(challenger.descend.selector, 1024));

        assertTrue(outerOk, "el marco exterior debe conservar gas para reportar el corte");
        (uint256 reached, uint8 terminal) = abi.decode(result, (uint256, uint8));
        console.log("marcos recursivos alcanzados con cap 30M:", reached);
        console.log("terminal (2=reveal revert, 3=child fail):", terminal);

        assertLt(reached, 1024, "30M no deben alcanzar la profundidad maxima");
        assertTrue(terminal == 2 || terminal == 3, "el reveal profundo no debe completar");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertEq(core.credits(address(challenger)), 0, "sin bounty ni devolucion clasificada como fault");
        assertEq(core.credits(agent), 0, "el agente tampoco cobra por el intento fallido");
    }
}
