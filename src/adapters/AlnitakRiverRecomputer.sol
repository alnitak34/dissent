// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "../IRecomputer.sol";
import {PokerEval} from "./PokerEval.sol";

/// @title AlnitakRiverRecomputer — el adaptador de poker
/// @notice Port de _exact_river_mix() de strategy.py (alnitak34/poker-bot,
///         commit 84dbf79). La aritmetica esta medida contra el Python: los tres
///         spots de test_river_exacto.py dan el mismo valor hasta el ultimo
///         digito de los 18.
///
/// LA EVIDENCIA ES UNA REGLA, NO UNA LISTA
/// Si el retador pudiera mandar una lista de manos, elegiria las N mas fuertes
/// que esten dentro del tier y fabricaria el resultado que quiera. El subconjunto
/// y el minimo de combinaciones son chequeos de BUENA FORMA, no de CORRECCION.
/// Por eso aca el retador NO elige manos: propone uno de tres tiers de precio
/// enumerados en este contrato, y el contrato enumera las 990 combinaciones el
/// mismo y filtra con el predicado de ese tier.
///
/// LA LISTA BLANCA SON LOS TRES TIERS QUE YA EXISTEN EN _in_range
/// No se inventa ninguno. Son el vocabulario del propio modelo, ya en produccion,
/// con la frontera del 65% justificada en el codigo del bot contra medicion de
/// campo. Inventar un cuarto tier seria inventar un numero, que es justo lo que
/// las reglas del proyecto prohiben.
///
///   TIER 0  MEDIUM   (price <= 0.28)   edge >= 1
///   TIER 1  LARGE    (price <= 0.333)  edge >= 2 || overpair
///   TIER 2  OVERBET  (price >  0.333)  edge >= 3 || overpair || edge == 0
///
/// Los tres NO estan anidados, y es a proposito: OVERBET incluye edge == 0, o
/// sea faroles puros. Un rango de sobreapuesta es POLARIZADO, no estrecho. Por
/// eso NO se exige que el tier propuesto sea subconjunto del declarado: eso
/// prohibiria el challenge mas significativo de todos, el que dice "no estabas
/// ante una apuesta media, estabas ante una sobreapuesta y su rango era
/// polarizado".
///
/// EN EL RIVER NO HAY PROYECTOS
/// has_strong_draw() de strategy.py devuelve False para len(board) >= 5. Asi que
/// _in_range se reduce a edge y overpair, y este adaptador NO necesita portar
/// has_strong_draw en absoluto.
///
/// PUNTO FIJO
/// La tabla del modelo entra en basis points (1e4): los doce valores de _VR_MIX
/// tienen tres decimales como maximo, asi que 7190/1690/750 los representa
/// EXACTO, mientras que en flotante 0.719 no lo es. Los pesos van a WAD (1e18)
/// multiplicando por 1e14. El resultado sale en WAD.
contract AlnitakRiverRecomputer is IRecomputer {
    uint256 private constant BP_TO_WAD = 1e14; // 1e18 / 1e4

    /// @dev Espejo de _EQR_MIN_COMBOS de strategy.py. Un tier que sobre este
    ///      board deje menos combinaciones que esto es demasiado estrecho para
    ///      leer nada, y se cae a la enumeracion completa.
    uint256 public constant MIN_COMBOS = 6;

    uint8 public constant TIER_MEDIUM = 0;
    uint8 public constant TIER_LARGE = 1;
    uint8 public constant TIER_OVERBET = 2;
    uint8 public constant TIER_COUNT = 3;

    bytes32 private constant REASON_OK = bytes32(0);
    bytes32 private constant REASON_BAD_LENGTH = "EVIDENCE_BAD_LENGTH";
    bytes32 private constant REASON_UNKNOWN_TIER = "UNKNOWN_TIER";

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    /// @dev Identidad del modelo. Si manana cambia _VR_MIX o el ladder de tiers,
    ///      esto tiene que cambiar, y los compromisos viejos quedan marcados.
    function domain() external pure returns (bytes32) {
        return "alnitak.river.mix.v1";
    }

    // ── decodificacion ────────────────────────────────────────────────────────

    struct Inputs {
        uint8[2] hole;
        uint8[5] board;
        uint256[3] mixBp; // (p1, p2, p3) en basis points
        uint256 priceBp; // declarado y registrado; NO se usa en el calculo
    }

    function decodeInputs(bytes calldata inputs) public pure returns (Inputs memory) {
        return abi.decode(inputs, (Inputs));
    }

    // ── validacion ────────────────────────────────────────────────────────────

    /// @notice Con la evidencia siendo una regla y no una lista, esto es casi
    ///         todo lo que queda: que sea un tier conocido. No hay subconjunto
    ///         que comprobar, ni bitmap anti-repetidos, ni minimo de manos,
    ///         porque el retador no elige manos.
    function validateEvidence(bytes calldata, bytes calldata evidence)
        external
        pure
        returns (bool ok, bytes32 reason)
    {
        if (evidence.length != 32) return (false, REASON_BAD_LENGTH);
        uint256 tier = abi.decode(evidence, (uint256));
        if (tier >= TIER_COUNT) return (false, REASON_UNKNOWN_TIER);
        return (true, REASON_OK);
    }

    // ── el calculo ────────────────────────────────────────────────────────────

    /// @notice Evidencia vacia -> enumeracion completa (el valor base, el mismo
    ///         que da _exact_river_mix con `fuente = combos`).
    ///         Evidencia = abi.encode(uint256 tier) -> solo las combinaciones que
    ///         cumplen el predicado de ese tier.
    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        Inputs memory p = abi.decode(inputs, (Inputs));
        bool filtrar = evidence.length == 32;
        uint256 tier = filtrar ? abi.decode(evidence, (uint256)) : 0;
        if (filtrar && tier >= TIER_COUNT) revert("UNKNOWN_TIER");
        // uint8(tier) no trunca en ninguno de los dos caminos:
        // - evidence.length != 32 -> filtrar = false -> tier = 0, el literal.
        // - evidence.length == 32 -> filtrar = true -> la linea de arriba revierte
        //   si tier >= TIER_COUNT (3), asi que aca tier vale 0, 1 o 2.
        // Sin ese guard, uint8(256) seria 0 y 256 se leeria como MEDIUM.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(_exact(p, filtrar, uint8(tier)));
    }

    /// @notice El tier que implica un precio, con los mismos cortes que _in_range.
    ///         Informativo: el retador puede proponer cualquiera de los tres.
    function tierForPrice(uint256 priceBp) public pure returns (uint8) {
        if (priceBp <= 2800) return TIER_MEDIUM;
        if (priceBp <= 3330) return TIER_LARGE;
        return TIER_OVERBET;
    }

    /// @notice board_floor_cat() de strategy.py para 5 cartas. Se CALCULA, no se
    ///         recibe: recibirla seria aceptar un numero del agente.
    function boardFloorCat(uint8[5] memory board) public pure returns (uint256) {
        uint256 rankMask;
        uint256[15] memory rc;
        uint256[4] memory suitMask;
        uint256[4] memory suitCount;
        for (uint256 i = 0; i < 5; i++) {
            uint256 r = uint256(board[i]) >> 2;
            uint256 s = uint256(board[i]) & 3;
            rc[r] += 1;
            // `1 << r` es el bit r de la mascara: el literal va a la izquierda a
            // proposito. incorrect-shift solo mira si el operando izquierdo es un
            // literal y el derecho no; aca r vale 0..14 porque rc[r], un
            // uint256[15], revierte en la linea de arriba si no.
            rankMask |= (1 << r); // forge-lint: disable-line(incorrect-shift)
            suitMask[s] |= (1 << r); // forge-lint: disable-line(incorrect-shift)
            suitCount[s] += 1;
        }
        uint256 flushSuit = 4;
        for (uint256 s = 0; s < 4; s++) {
            if (suitCount[s] >= 5) flushSuit = s;
        }
        if (flushSuit < 4 && PokerEval.bestStraight(suitMask[flushSuit]) != 0) return 8;

        uint256 m1;
        uint256 m2;
        for (uint256 r = 2; r <= 14; r++) {
            uint256 c = rc[r];
            if (c > m1) {
                m2 = m1;
                m1 = c;
            } else if (c > m2) {
                m2 = c;
            }
        }
        if (m1 >= 4) return 7;
        if (m1 == 3 && m2 >= 2) return 6;
        if (flushSuit < 4) return 5;
        if (PokerEval.bestStraight(rankMask) != 0) return 4;
        if (m1 == 3) return 3;
        if (m1 == 2 && m2 == 2) return 2;
        if (m1 == 2) return 1;
        return 0;
    }

    /// @dev El predicado de _in_range, sin la rama de proyectos porque en el
    ///      river has_strong_draw es siempre False.
    function _inTier(uint8 tier, uint256 edge, bool overpair) private pure returns (bool) {
        if (tier == TIER_MEDIUM) return edge >= 1;
        if (tier == TIER_LARGE) return edge >= 2 || overpair;
        return edge >= 3 || overpair || edge == 0;
    }

    function _mazo(uint8[2] memory hole, uint8[5] memory board) private pure returns (uint8[45] memory mazo) {
        uint256 n;
        for (uint256 r = 2; r <= 14; r++) {
            for (uint256 s = 0; s < 4; s++) {
                // Cotas de los bucles: `r = 2; r <= 14` da 2 <= r <= 14 y
                // `s = 0; s < 4` da 0 <= s <= 3. Entonces 2*4+0 = 8 <= r*4+s <=
                // 14*4+3 = 59, que entra en uint8. Sin assert en el bucle: la cota
                // ya la fijan los limites, y un chequeo por vuelta es gas gratis
                // perdido. Ademas, ensanchar cualquier limite desborda mazo[45]
                // (panic) mucho antes de que r*4+s llegue a 256.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint8 c = uint8(r * 4 + s);
                if (c == hole[0] || c == hole[1]) continue;
                if (c == board[0] || c == board[1] || c == board[2] || c == board[3] || c == board[4]) continue;
                mazo[n] = c;
                n++;
            }
        }
    }

    /// @dev Los pesos por bucket, resueltos desde los cuatro tramos de
    ///      _mix_sample. En cada tramo se toma el PRIMER bucket no vacio, no la
    ///      cabeza del orden: los buckets vacios existen y su masa cae al
    ///      siguiente.
    function _pesos(uint256[3] memory mixBp, uint256[4] memory n)
        private
        pure
        returns (uint256[4] memory peso, bool ok)
    {
        uint256[4] memory probBp;
        probBp[0] = mixBp[2]; // p3
        probBp[1] = mixBp[1] - mixBp[2]; // p2 - p3
        probBp[2] = mixBp[0] - mixBp[1]; // p1 - p2
        probBp[3] = 10000 - mixBp[0]; // 1 - p1

        uint8[4][4] memory orden;
        orden[0] = [3, 2, 1, 0];
        orden[1] = [2, 3, 1, 0];
        orden[2] = [1, 2, 3, 0];
        orden[3] = [0, 1, 2, 3];

        for (uint256 t = 0; t < 4; t++) {
            if (probBp[t] == 0) continue;
            bool puesto;
            for (uint256 q = 0; q < 4; q++) {
                uint256 k = orden[t][q];
                if (n[k] != 0) {
                    peso[k] += probBp[t] * BP_TO_WAD;
                    puesto = true;
                    break;
                }
            }
            if (!puesto) return (peso, false);
        }
        ok = true;
    }

    /// @dev Las cuatro poblaciones de una sola pasada: la completa (el valor
    ///      base) y la del tier propuesto. En struct y no en variables sueltas
    ///      para no desbordar la pila de la EVM en el bucle de 990 vueltas.
    struct Tally {
        uint256[4] n;
        uint256[4] acc;
        uint256[4] nAll;
        uint256[4] accAll;
    }

    struct Ctx {
        uint256 floorCat;
        uint256 boardTop;
        uint256 mia;
    }

    function _ctx(Inputs memory p) private pure returns (Ctx memory c) {
        c.floorCat = boardFloorCat(p.board);
        for (uint256 i = 0; i < 5; i++) {
            uint256 r = uint256(p.board[i]) >> 2;
            if (r > c.boardTop) c.boardTop = r;
        }
        uint8[7] memory buf;
        buf[0] = p.hole[0];
        buf[1] = p.hole[1];
        for (uint256 i = 0; i < 5; i++) {
            buf[2 + i] = p.board[i];
        }
        c.mia = PokerEval.eval7(buf);
    }

    /// @dev Acumula en ENTEROS: 2*victorias + empates por bucket.
    function _enumerar(Inputs memory p, Ctx memory c, bool filtrar, uint8 tier)
        private
        pure
        returns (Tally memory t)
    {
        uint8[45] memory mazo = _mazo(p.hole, p.board);
        uint8[7] memory buf;
        for (uint256 i = 0; i < 5; i++) {
            buf[2 + i] = p.board[i];
        }
        for (uint256 i = 0; i < 45; i++) {
            buf[0] = mazo[i];
            for (uint256 j = i + 1; j < 45; j++) {
                buf[1] = mazo[j];
                _contar(t, c, buf, filtrar, tier);
            }
        }
    }

    function _contar(Tally memory t, Ctx memory c, uint8[7] memory buf, bool filtrar, uint8 tier) private pure {
        uint256 v = PokerEval.eval7(buf);
        uint256 cat = v >> 20;
        uint256 edge = cat <= c.floorCat ? 0 : cat - c.floorCat;
        uint256 k = edge > 3 ? 3 : edge;
        uint256 aporte = c.mia > v ? 2 : (c.mia == v ? 1 : 0);

        t.nAll[k] += 1;
        t.accAll[k] += aporte;

        if (!filtrar) return;
        uint256 ra = uint256(buf[0]) >> 2;
        bool overpair = (ra == (uint256(buf[1]) >> 2)) && ra > c.boardTop;
        if (_inTier(tier, edge, overpair)) {
            t.n[k] += 1;
            t.acc[k] += aporte;
        }
    }

    /// @dev Combina cuatro terminos al final, en orden 0,1,2,3, para que el
    ///      resultado no dependa del orden de recorrido.
    function _exact(Inputs memory p, bool filtrar, uint8 tier) private pure returns (uint256) {
        Ctx memory c = _ctx(p);
        Tally memory t = _enumerar(p, c, filtrar, tier);

        if (!filtrar) return _combinar(p.mixBp, t.nAll, t.accAll);

        // Espejo del guard de strategy.py: un rango demasiado estrecho no se usa.
        // Cae a la enumeracion completa, que es conservador: solo puede hacer
        // fallar un challenge, nunca hacerlo triunfar sin merecerlo.
        if (t.n[0] + t.n[1] + t.n[2] + t.n[3] < MIN_COMBOS) {
            return _combinar(p.mixBp, t.nAll, t.accAll);
        }
        return _combinar(p.mixBp, t.n, t.acc);
    }

    function _combinar(uint256[3] memory mixBp, uint256[4] memory n, uint256[4] memory acc)
        private
        pure
        returns (uint256)
    {
        (uint256[4] memory peso, bool ok) = _pesos(mixBp, n);
        if (!ok) return 0;
        uint256 t0 = n[0] == 0 ? 0 : (peso[0] * acc[0]) / n[0];
        uint256 t1 = n[1] == 0 ? 0 : (peso[1] * acc[1]) / n[1];
        uint256 t2 = n[2] == 0 ? 0 : (peso[2] * acc[2]) / n[2];
        uint256 t3 = n[3] == 0 ? 0 : (peso[3] * acc[3]) / n[3];
        return (t0 + t1 + t2 + t3) / 2;
    }
}
