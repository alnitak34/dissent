// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";

/// @title Deploy — despliegue de Dissent en Monad testnet (chain id 10143).
/// @notice Ninguno de los dos contratos tiene argumentos de constructor. La clave
///         NO vive aca: la aporta el keystore/cuenta de Foundry por fuera del repo
///         (--account / --ledger / etc.). Este script no contiene claves, ni
///         mnemonics, ni direcciones personales, ni RPC con credenciales.
///
///         Simular (sin transmitir), una sola linea:
///           forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz
///         Transmitir (solo cuando se decida, con una cuenta real), una sola linea:
///           forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz --account <keystore> --broadcast
contract Deploy is Script {
    uint256 internal constant MONAD_TESTNET_CHAIN_ID = 10143;

    function run() external returns (DissentCore core, AlnitakRiverRecomputer recomputer) {
        require(block.chainid == MONAD_TESTNET_CHAIN_ID, "no es Monad testnet (chain id 10143)");

        vm.startBroadcast();
        core = new DissentCore();
        recomputer = new AlnitakRiverRecomputer();
        vm.stopBroadcast();

        console.log("chainid               ", block.chainid);
        console.log("DissentCore           ", address(core));
        console.log("AlnitakRiverRecomputer", address(recomputer));

        // Chequeos de lectura sobre lo recien creado.
        require(core.MIN_WINDOW() == 1 hours, "MIN_WINDOW != 1 hours");
        require(core.escrowed() == 0, "escrowed != 0");
        require(recomputer.scale() == 1e18, "scale != 1e18");
        require(recomputer.domain() == bytes32("alnitak.river.mix.v1"), "domain inesperado");
    }
}
