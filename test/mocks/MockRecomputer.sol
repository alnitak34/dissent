// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "../../src/IRecomputer.sol";

/// @notice Recalculador barato para probar el PROTOCOLO sin pagar 17M de gas por
///         llamada. inputs = abi.encode(int256 base); evidence vacia devuelve el
///         base, evidence = abi.encode(int256 v) devuelve v.
contract MockRecomputer is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "mock.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external pure returns (bool, bytes32) {
        if (evidence.length != 0 && evidence.length != 32) return (false, "BAD_LENGTH");
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        if (evidence.length == 32) return abi.decode(evidence, (int256));
        return abi.decode(inputs, (int256));
    }
}

/// @notice Rechaza toda evidencia. Para probar el camino de EvidenceRejected.
contract RejectingRecomputer is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "reject.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external pure returns (bool, bytes32) {
        if (evidence.length == 0) return (true, bytes32(0));
        return (false, "ALWAYS_NO");
    }

    function recompute(bytes calldata inputs, bytes calldata) external pure returns (int256) {
        return abi.decode(inputs, (int256));
    }
}

/// @notice Revierte siempre en recompute. Para probar RecomputerReverted.
contract RevertingRecomputer is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "revert.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata, bytes calldata) external pure returns (int256) {
        revert("nope");
    }
}

/// @notice Intenta reentrar DissentCore desde recompute. Como el nucleo invoca
///         por STATICCALL, cualquier escritura revierte.
interface ICoreLike {
    function withdrawCredit() external;
}

contract ReentrantRecomputer is IRecomputer {
    address public core;

    constructor(address c) {
        core = c;
    }

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "reentrant.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata) external view returns (int256) {
        // esto tiene que fallar: estamos dentro de un STATICCALL
        (bool ok,) = core.staticcall(abi.encodeWithSelector(ICoreLike.withdrawCredit.selector));
        require(!ok, "la reentrada escribio estado");
        return abi.decode(inputs, (int256));
    }
}

/// @notice Un agente que rechaza MON. Prueba que el patron pull impide que
///         bloquee los challenges fallidos.
contract RejectingAgent {
    receive() external payable {
        revert("no MON");
    }

    function commitOn(address core, bytes calldata data) external payable returns (bytes memory) {
        (bool ok, bytes memory ret) = core.call{value: msg.value}(data);
        require(ok, "commit fallo");
        return ret;
    }
}
