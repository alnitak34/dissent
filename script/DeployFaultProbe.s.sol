// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IRecomputer} from "../src/IRecomputer.sol";

/// @notice SOLO PARA TESTNET: funciona al crear el compromiso y revierte
///         deliberadamente al recalcular evidencia no vacia. No es un adaptador
///         de produccion ni prueba que otros adaptadores sean seguros.
contract FaultProbeRecomputer is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1;
    }

    function domain() external pure returns (bytes32) {
        return bytes32("dissent.fault.probe.v1");
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external pure returns (bool, bytes32) {
        return (evidence.length == 32, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        if (evidence.length != 0) revert("INTENTIONAL_TEST_FAULT");
        return abi.decode(inputs, (int256));
    }
}

/// @notice Despliega SOLO el adaptador de prueba. No crea un compromiso ni
///         mueve fondos al nucleo. La simulacion sin --broadcast no transmite.
contract DeployFaultProbe is Script {
    function run() external returns (FaultProbeRecomputer probe) {
        require(block.chainid == 10143, "solo Monad Testnet");
        vm.startBroadcast();
        probe = new FaultProbeRecomputer();
        vm.stopBroadcast();
        require(probe.scale() == 1, "escala inesperada");
        require(probe.domain() == bytes32("dissent.fault.probe.v1"), "dominio inesperado");
        console.log("FaultProbeRecomputer (testnet only)", address(probe));
    }
}
