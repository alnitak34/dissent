// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";
import {PokerEval} from "../src/adapters/PokerEval.sol";

contract PokerEvalHarness {
    function eval7(uint8[7] memory cards) external pure returns (uint256) {
        return PokerEval.eval7(cards);
    }
}

/// @notice Los caminos que pasan por `1 << r` y que las manos de los otros tests
///         no recorren: escalera y escalera de color en el board, y los kickers
///         de un color. Invertir cualquiera de los cinco desplazamientos
///         (`r << 1`) tumba al menos uno de estos tests o de los ya existentes.
///
/// INDEPENDIENTES DE strategy.py: los valores esperados NO salen del Python.
/// Salen de las reglas del poker (un board 2-3-4-5-6 es escalera, 9-T-J-Q-K del
/// mismo palo es escalera de color) y del empaquetado documentado en PokerEval
/// (score = cat*16^5 + t1*16^4 + ... + t5). Si el Python y estos tests algun dia
/// discrepan, hay que mirar los dos: estos no heredan un error del Python.
///
/// carta uint8 = rango*4 + palo, palo c=0 d=1 h=2 s=3
contract MascarasTest is Test {
    AlnitakRiverRecomputer rc;
    PokerEvalHarness ev;

    function setUp() public {
        rc = new AlnitakRiverRecomputer();
        ev = new PokerEvalHarness();
    }

    function test_board_escalera_da_categoria_4() public view {
        // 2c 3d 4h 5s 6c
        assertEq(rc.boardFloorCat([uint8(8), 13, 18, 23, 24]), 4);
    }

    function test_board_escalera_de_color_da_categoria_8() public view {
        // 9c Tc Jc Qc Kc
        assertEq(rc.boardFloorCat([uint8(36), 40, 44, 48, 52]), 8);
    }

    function test_color_empaqueta_sus_cinco_rangos() public view {
        // Ac Jc 9c 6c 3c 2d 8h: color de trebol, sin escalera ni pares
        uint256 esperado = (5 << 20) | (14 << 16) | (11 << 12) | (9 << 8) | (6 << 4) | 3;
        assertEq(ev.eval7([uint8(56), 44, 36, 24, 12, 9, 34]), esperado);
    }
}
