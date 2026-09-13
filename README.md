# Dissent — apuestas sobre afirmaciones deterministas

Un agente afirma que `f(entradas)` cumple un umbral, escrowea una recompensa en
MON y abre una ventana. Cualquiera puede traer evidencia nueva y, si con esa
evidencia el valor cruza el umbral, se lleva la recompensa y su depósito. Si no
cruza, pierde el depósito.

**El contrato nunca acepta un número de nadie.** Ni del agente ni del retador.
Todo valor que decide plata lo calcula el contrato llamando al recalculador.

## Los tres contratos

| Archivo | Qué es |
|---|---|
| `src/IRecomputer.sol` | La frontera entre el protocolo y el dominio. Una sola función de valor. |
| `src/DissentCore.sol` | El protocolo. No sabe de póker. Sin owner, sin `withdraw()`, sin pausa. |
| `src/adapters/AlnitakRiverRecomputer.sol` | El adaptador de póker, port de `_exact_river_mix()` de `strategy.py`. |
| `src/adapters/PokerEval.sol` | Evaluador de manos de 7 cartas, usado solo por el adaptador. |

`src/` tiene exactamente dos archivos: el protocolo y la frontera. Todo lo que
sepa de un dominio vive en `src/adapters/`. Eso no es prolijidad, es una
afirmación comprobable: borrá `src/adapters/`, `test/AlnitakRiverRecomputer.t.sol`
y `test/ManoReal.t.sol`, y corré `forge test`. Compila y pasan los 27 tests del
núcleo. (Hay que sacar también los tests, no solo el adaptador: `forge` compila
el árbol entero antes de filtrar, así que `--match-path` no alcanza.)

## Verificación de las entradas: fuera de la cadena

**Esto es importante y no hay que confundirlo.**

El contrato verifica **aritmética sobre entradas declaradas**. No verifica que
las entradas hayan ocurrido. El board, las cartas, el bote y el precio no
existen en la cadena: el agente los declara, y el contrato los toma como dados.

Ahora bien, en este dominio concreto **sí se pueden verificar, por terceros y sin
credenciales**. La arena de dev.fun expone endpoints tRPC públicos y sin
autenticación:

```
https://arena.dev.fun/api/arena.getTexasReplay?input={"json":{"tableId":"..."}}
https://arena.dev.fun/api/arena.getTexasTables?input={"json":{"arenaId":"...","agentId":"...","limit":100}}
```

Cada replay trae `events[]` con `payload.pot`, `allowedActions` completo,
`snapshot.seats` con las cartas, y `payload.reasoning` — la etiqueta de la
decisión que el bot tomó ese día. Con el `tableId` y el `sequence` de una
decisión, cualquiera puede bajar el replay y comprobar, a mano, que las cartas,
el board, el bote y el precio del compromiso son los que figuran ahí.

Tres cosas que hay que tener claras sobre esa verificación:

1. **La hace un tercero, no la cadena.** Si alguien compromete una mano que nunca
   jugó, el contrato la procesará con todo rigor igual. Lo único que ocurre es
   que cualquiera puede darse cuenta bajando el replay, y no comprar esa
   afirmación.
2. **Depende de que dev.fun siga sirviendo esos endpoints.** No es una garantía
   criptográfica; es un archivo de terceros que hoy está abierto.
3. **Los datos vienen contaminados** y hay que saber leerlos: `snapshot.seats`
   trae las cartas de los seis asientos, el snapshot es el estado DESPUÉS de la
   acción (hay que usar `payload.stackBefore`), y `snapshot.boardCards` trae el
   board de la calle siguiente en 71 de 938 casos medidos. Reconstruir mal es
   fácil.

## Los seis límites declarados

No son pendientes. Son lo que este diseño no puede hacer.

1. **Que las entradas sean verdad.** Ver arriba. Es el límite más grande y
   ninguno de los otros cinco importa si este no se entiende.
2. **Que el rango de la evidencia sea el correcto.** El retador elige uno de tres
   tiers canónicos, no manos sueltas, así que no puede fabricar un rango a
   medida. Pero elegir entre tres sigue siendo elegir. El contrato no puede
   decir cuál era el rango de verdad del rival: eso es una afirmación de modelo,
   no de aritmética.
3. **Que el recalculador sea determinista.** `view` puede leer `block.number` o
   storage mutable. El núcleo no puede probar pureza. Mitigación parcial: guarda
   y reemite `domain()`, y el recalculador debería ser inmutable y con fuente
   verificada — pero eso es confianza social, no criptografía.
4. **Que la acción del agente se haya seguido del valor.** El compromiso dice
   "hice X porque f ≥ T". Nada ata esa frase a una acción real en una mesa real.
   `action` es texto, con el mismo estatuto que el `label` de Once.
5. **Que la tabla del modelo sea correcta.** `_VR_MIX` son proporciones medidas
   sobre 1.352 apuestas de rivales **que llegaron a showdown**, y ese sesgo está
   documentado en el código del bot: las manos que ganaron sin mostrar son
   invisibles, así que la tabla sobreestima la fuerza del rival. Un challenge
   exitoso demuestra que el número da distinto con otro rango, no que el número
   nuevo sea el bueno.
6. **Que el agente y el retador sean personas distintas.** Sybil.

## Los ataques que siguen abiertos

**Sybil del propio agente.** Prohibir `msg.sender == agent` no sirve: una segunda
billetera lo evade. El challenge en dos fases le quita la parte peor —ya no puede
ver la evidencia ajena y copiarla— pero sigue pudiendo sellar en paralelo a
ciegas con su propia evidencia. Si acierta con el tier que gana, recupera su
propia plata y cierra el compromiso antes que el retador honesto. La ventaja
ahora es que tiene que apostar a ciegas y arriesgar el depósito, no copiar sobre
seguro.

**Umbral laxo a propósito.** El agente elige un umbral que nada cruza, recupera
su recompensa en el reclaim, y queda un registro que parece robusto. No le roba a
nadie; degrada el significado. Es un problema de mercado, no de contrato.

**Un retador honesto que no llega a revelar pierde el depósito.** Es el costo
elegido de que el sello sea un compromiso y no una opción gratis. Contra eso está
la ventana de 7.200 bloques.

## El puente: de una mano real a los bytes

`bridge/` convierte una decisión concreta de una mesa real en los bytes exactos
que espera `DissentCore.commit`, y permite comprobar después que esos bytes son
esa mano. **Solo biblioteca estándar de Python** — ni web3, ni eth-abi, ni
pycryptodome. `keccak256` y la codificación ABI están implementados a mano y
comprobados contra `cast keccak` y `cast abi-encode`; `python bridge/mano.py`
corre ese autochequeo.

```bash
# armar los bytes de una mano
python bridge/armar_commit.py cmtr0ktvzxa5q15he4ekev8ub 29

# comprobar que unos bytes son esa mano, bajando el replay del endpoint público
python bridge/verificar.py 0x0000...0e2d cmtr0ktvzxa5q15he4ekev8ub
```

`verificar.py` no necesita este repo, ni el corpus, ni ninguna credencial: baja
el replay del endpoint abierto de arena.dev.fun y re-deriva cada campo. Sin
`--seq` recorre todas las decisiones de river de la mesa y dice cuál encaja.
Devuelve 0 si coincide, 1 si no, y en ese caso lista campo por campo qué dicen
los bytes y qué dice el replay.

La mano de ejemplo (`Qd Ad` en `2s 2c Tc Qc 9d`, heads-up, 45 a pagar sobre 79)
está en `test/ManoReal.t.sol` como constante hexadecimal literal, copiada de la
salida del puente: si el codificador de Python cambia, ese test se cae.

**Dos cosas de los bytes NO salen del replay**, y los dos scripts lo dicen cada
vez que corren:

- `mixBp`. El replay fija la *clase* de presión (`bet/big`, `multi/small`, …);
  los tres números de esa fila son la tabla del modelo, el límite 5 de acá
  arriba. Rechazar la tabla es rechazar el compromiso entero.
- El umbral. Es una elección del agente. `armar_commit.py` lo deriva del precio
  por la regla `umbral = precio`, y `verificar.py --umbral` comprueba esa regla,
  pero la regla es una decisión, no un dato de la mano.

## Correr los tests

```bash
forge build
forge test -vv
```

53 tests, sin red, sin claves, sin desplegar nada.
