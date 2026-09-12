// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PokerEval — port de eval7() de strategy.py (alnitak34/poker-bot, 84dbf79)
/// @notice Evalua 7 cartas y devuelve un score comparable con `>`.
///
/// TECNICA ELEGIDA: mascaras de bits + contadores, SIN ordenamiento.
///
/// El Python ordena listas tres veces por evaluacion (sorted(ranks), sorted por
/// (count, rank), sorted del palo del color). Ordenar en Solidity cuesta caro y
/// no hace falta: los rangos van de 2 a 14, o sea 13 valores, que entran en una
/// mascara de 16 bits. Con `rankMask` (que rangos hay), `rankCount[r]` (cuantos
/// de cada uno) y `suitMask[s]` (que rangos hay de cada palo) se contesta todo
/// escaneando de 14 hacia abajo. Es la representacion estandar para esto y da el
/// MISMO resultado que el Python, no una aproximacion.
///
/// EL SCORE: Python devuelve tuplas de forma distinta segun la categoria y las
/// compara lexicograficamente. Aca se empaquetan en un uint256:
///
///     score = cat * 16^5 + t1*16^4 + t2*16^3 + t3*16^2 + t4*16 + t5
///
/// Los rangos valen 2..14, entran en 4 bits, y los huecos van en 0. Comparar dos
/// scores con `>` da exactamente el mismo orden que comparar las tuplas de
/// Python, porque dentro de una categoria los desempates ocupan las mismas
/// posiciones y en el mismo orden.
///
/// CARTA: un uint8 = rango*4 + palo. Rango 2..14, palo 0..3.
library PokerEval {
    /// @dev Mayor escalera dentro de una mascara de rangos. 0 si no hay.
    ///      Con as presente se agrega el bit 1 para la rueda A-2-3-4-5, igual que
    ///      `if 14 in rs: rs.add(1)` en Python. Devuelve el rango MAS ALTO de la
    ///      escalera, asi que la rueda devuelve 5.
    function bestStraight(uint256 mask) internal pure returns (uint256) {
        if (mask & (1 << 14) != 0) mask |= (1 << 1);
        for (uint256 top = 14; top >= 5; top--) {
            uint256 need = uint256(0x1F) << (top - 4);
            if (mask & need == need) return top;
        }
        return 0;
    }

    function _pack(uint256 cat, uint256 t1, uint256 t2, uint256 t3, uint256 t4, uint256 t5)
        private
        pure
        returns (uint256)
    {
        return (cat << 20) | (t1 << 16) | (t2 << 12) | (t3 << 8) | (t4 << 4) | t5;
    }

    /// @dev El rango mas alto con exactamente (o al menos) cierta cantidad.
    function _highestWithCount(uint256[15] memory rc, uint256 c, bool atLeast, uint256 skip)
        private
        pure
        returns (uint256)
    {
        for (uint256 r = 14; r >= 2; r--) {
            if (r == skip) continue;
            if (atLeast ? rc[r] >= c : rc[r] == c) return r;
        }
        return 0;
    }

    /// @dev Los k rangos mas altos presentes en la mascara, saltando hasta dos.
    function _topK(uint256 mask, uint256 k, uint256 skipA, uint256 skipB)
        private
        pure
        returns (uint256[5] memory out)
    {
        uint256 n;
        for (uint256 r = 14; r >= 2 && n < k; r--) {
            if (r == skipA || r == skipB) continue;
            if (mask & (1 << r) != 0) {
                out[n] = r;
                n++;
            }
        }
    }

    /// @notice Evalua 7 cartas. Mismo resultado que eval7() de strategy.py.
    function eval7(uint8[7] memory cards) internal pure returns (uint256) {
        uint256 rankMask;
        uint256[15] memory rc;
        uint256[4] memory suitMask;
        uint256[4] memory suitCount;

        for (uint256 i = 0; i < 7; i++) {
            uint256 r = uint256(cards[i]) >> 2;
            uint256 s = uint256(cards[i]) & 3;
            rc[r] += 1;
            rankMask |= (1 << r);
            suitMask[s] |= (1 << r);
            suitCount[s] += 1;
        }

        // -- color / escalera de color -------------------------------------
        uint256 flushSuit = 4;
        for (uint256 s = 0; s < 4; s++) {
            if (suitCount[s] >= 5) flushSuit = s;
        }
        if (flushSuit < 4) {
            uint256 sf = bestStraight(suitMask[flushSuit]);
            if (sf != 0) return _pack(8, sf, 0, 0, 0, 0);
        }

        // -- cuantas veces se repite el rango mas repetido -------------------
        uint256 maxc;
        for (uint256 r = 2; r <= 14; r++) {
            if (rc[r] > maxc) maxc = rc[r];
        }

        // -- poker ----------------------------------------------------------
        if (maxc == 4) {
            uint256 quad = _highestWithCount(rc, 4, false, 0);
            uint256 kick = _topK(rankMask, 1, quad, 0)[0];
            return _pack(7, quad, kick, 0, 0, 0);
        }

        // -- full: trio + otro grupo de 2 o mas ------------------------------
        if (maxc == 3) {
            uint256 trips = _highestWithCount(rc, 3, false, 0);
            uint256 pair = _highestWithCount(rc, 2, true, trips);
            if (pair != 0) return _pack(6, trips, pair, 0, 0, 0);
        }

        // -- color ----------------------------------------------------------
        if (flushSuit < 4) {
            uint256[5] memory f = _topK(suitMask[flushSuit], 5, 0, 0);
            return _pack(5, f[0], f[1], f[2], f[3], f[4]);
        }

        // -- escalera --------------------------------------------------------
        uint256 st = bestStraight(rankMask);
        if (st != 0) return _pack(4, st, 0, 0, 0, 0);

        // -- trio ------------------------------------------------------------
        if (maxc == 3) {
            uint256 trips = _highestWithCount(rc, 3, false, 0);
            uint256[5] memory k = _topK(rankMask, 2, trips, 0);
            return _pack(3, trips, k[0], k[1], 0, 0);
        }

        // -- dos pares --------------------------------------------------------
        if (maxc == 2) {
            uint256 p1 = _highestWithCount(rc, 2, false, 0);
            uint256 p2 = _highestWithCount(rc, 2, false, p1);
            if (p2 != 0) {
                uint256 kick = _topK(rankMask, 1, p1, p2)[0];
                return _pack(2, p1, p2, kick, 0, 0);
            }
            uint256[5] memory k = _topK(rankMask, 3, p1, 0);
            return _pack(1, p1, k[0], k[1], k[2], 0);
        }

        // -- carta alta --------------------------------------------------------
        uint256[5] memory h = _topK(rankMask, 5, 0, 0);
        return _pack(0, h[0], h[1], h[2], h[3], h[4]);
    }

    /// @notice Solo la categoria (0..8), que es lo que usa board_floor_cat y el bucketeo.
    function categoryOf(uint256 score) internal pure returns (uint256) {
        return score >> 20;
    }
}
