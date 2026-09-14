# Dissent — apuestas sobre afirmaciones deterministas

Dissent es un protocolo en Monad para afirmaciones numéricas **falsables**.

- Un agente publica **entradas**, un **umbral** y una **acción declarada**, y
  escrowea una **recompensa** en MON.
- El contrato **no acepta del agente ni del retador el número que decide el
  dinero**. Ese valor lo obtiene llamando a un **recomputer** (un contrato que
  implementa `IRecomputer`) identificado por el compromiso.
- Cualquiera puede **sellar** evidencia y luego **revelarla**. El contrato corre
  el mismo recomputer con esa evidencia y compara contra el umbral.
- Si con la evidencia el valor **cruza** el umbral, el retador cobra recompensa +
  su depósito. Si no cruza, el depósito va al agente.

**El resultado económico depende del recomputer elegido por el agente.** El
protocolo garantiza la mecánica (escrow, sellado en dos fases, pagos); la
**semántica** —qué significa el número y si es honesto— la define el adaptador.
Ver [Frontera de confianza](#frontera-de-confianza).

## Estado

Contrato **implementado, probado localmente y desplegado con código verificado en
Monad testnet**. **Auditoría externa pendiente.**

- `DissentCore`: [`0x6dCD...6758`](https://testnet.monadvision.com/address/0x6dCD184c9c0db42FCD0De731F9a2855b38916758)
- `AlnitakRiverRecomputer`: [`0x2a26...8E38`](https://testnet.monadvision.com/address/0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38)
- Recibos, bloques, costes y comandos de verificación: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)

Hay un adaptador de póker de ejemplo (`AlnitakRiverRecomputer`), un puente en
Python y una interfaz web de solo lectura que comprueba la primera ejecución
completa contra el RPC público. La indexación general de commitments y la
escritura desde una wallet siguen siendo trabajo futuro.

## Estructura de `src/`

| Archivo | Qué es |
|---|---|
| `src/IRecomputer.sol` | La frontera entre el protocolo y el dominio. Una sola función de valor. |
| `src/DissentCore.sol` | El protocolo. No sabe de póker. Sin owner, sin retiro administrativo del escrow, sin pausa y sin proxy. Los beneficiarios retiran sus propios créditos con `withdrawCredit()`. |
| `src/adapters/AlnitakRiverRecomputer.sol` | Adaptador de póker de ejemplo, port de `_exact_river_mix()` de `strategy.py`. |
| `src/adapters/PokerEval.sol` | Evaluador de manos de 7 cartas, usado solo por el adaptador. |

`src/` fuera de `adapters/` es solo el protocolo y la frontera: nada de un
dominio concreto vive ahí.

## Tabla de resultados de un challenge

| Estado / evento | Cuándo | Depósito | Recompensa | Significado |
|---|---|---|---|---|
| **Challenged** | evidencia válida y `recompute` **cruza** el umbral | vuelve al retador (dentro del payout) | al retador | la afirmación fue refutada con esa evidencia |
| **ChallengeFailed** | evidencia válida y `recompute` **no cruza**; sigue `Open` | al agente | — | la afirmación se sostuvo frente a esa evidencia |
| **ChallengeRejected** | `validateEvidence` devolvió `false` canónico; sello liquidado; sigue `Open` | **vuelve al retador** | — | evidencia malformada: **inconcluso**, el agente no cosecha |
| **Faulted** | el adaptador revirtió, hizo OOG, o devolvió ABI no canónico **teniendo el gas prometido** | vuelve al retador (dentro del payout) | al retador | **fallo técnico del adaptador**, NO una refutación de la afirmación |
| **ChallengeVoided** | otro retador ya resolvió | vuelve al retador | — | sin llamar al adaptador |
| **Reclaimed** | venció `windowEnds`, venció además el periodo conservador calculado desde el sello más reciente, y no hubo challenge exitoso | — | vuelve al agente | **NO significa "verificado"**: puede no haber habido challenges, o muchos `ChallengeRejected` |

`Reclaimed` significa que se cumplieron **las tres** condiciones: (1) venció
`windowEnds` (ya no se puede sellar); (2) venció además el **periodo conservador
calculado desde el sello más reciente** — `latestSealBlock + REVEAL_DELAY_BLOCKS +
REVEAL_WINDOW_BLOCKS` — si existió algún sello. El contrato **no** comprueba si
quedan sellos "vivos": espera ese plazo desde el último sello aunque ya haya sido
liquidado. Y (3) ningún challenge cruzó el umbral. **No** es `Verified`: solo dice
que nadie reveló un challenge exitoso antes del cierre.

## Frontera de confianza

> **El protocolo garantiza la mecánica; el adaptador define la semántica.**

- El agente **elige** el recomputer. Un adaptador puede devolver siempre `false`,
  o valores favorables al agente, sin que el núcleo lo note.
- `view` **no** es `pure`: el recomputer puede leer `block.number`,
  `block.timestamp`, `block.basefee` o storage mutable, y comportarse distinto
  según el contexto (por eso el sellado en dos fases y el modelo de gas).
- `domain()` es una **etiqueta**, no una prueba de honestidad.
- Un **proxy** o un adaptador con storage mutable puede **cambiar de
  comportamiento** después de que se creen compromisos contra él.
- Los resultados **valen tanto como el adaptador**. Dissent **no es un oráculo de
  verdad**.
- **Para producción**, el consumidor debe exigir adaptadores **auditados,
  inmutables, con fuente verificada y versión reconocible** (`domain()`), y tratar
  un adaptador desconocido como no confiable.

Contadores como "cuántos `ChallengeRejected` o `AdapterFaulted` acumuló un
compromiso" se **derivan indexando eventos**; el núcleo **no** los almacena.

## Gas y economía

- **Monad cobra el gas _limit_ declarado, no el gas usado.** Fijar mal el límite
  cuesta MON real.
- **Límite por transacción: 30.000.000 de gas.** La transacción completa del
  reveal (intrínseco + entrada + piso EIP-150 + liquidación) tiene que caber.
- `REFERENCE_GAS_PRICE = 100 gwei` (piso de base fee de Monad al momento de este
  diseño; **no** garantizado para siempre).
- `effectiveGasPrice = max(REFERENCE_GAS_PRICE, block.basefee)`, **fijado al
  commit** y guardado en el compromiso (parte de su identidad). No cambia después.
- `commit` exige `msg.value ≥ minGasBackedReward`, donde
  `minGasBackedReward = (txRequired + CHALLENGE_COMMIT_GAS) · effectiveGasPrice`.
  El depósito **no** entra: la recompensa cubre el gas del retador; su depósito le
  vuelve al ganar.

Política recomendada para el adaptador Alnitak (la que reporta el puente):
`validateGasLimit = 100_000`, `recomputeGasLimit = 20_000_000`,
`inputs = 352 bytes`, `maxEvidenceLen = 32`:

```
txRequired          = 20.975.348
+ CHALLENGE_COMMIT    200.000
total respaldado    = 21.175.348
mínimo de referencia = 21.175.348 × 100 gwei = 2,1175348 MON
```

El test `EconomicBackingTest.test_alnitak_politica_recomendada_R20M` afirma ese
valor exacto contra el contrato. (Configuración mínima ensayada, **histórica**:
`recomputeGasLimit = 18_000_000` → 1,9143602 MON; pero 18M deja **poco margen**
sobre el peor `recompute` medido de Alnitak, ~17,92M, así que **no** es la
recomendación actual — 20M sí.)

Esto cubre el **presupuesto de gas de referencia del protocolo**, **no** cualquier
gas limit que el retador elija declarar: si el retador manda una tx con un límite
mayor, Monad le cobra ese valor mayor y Dissent no garantiza la diferencia. Una
**subida posterior de `block.basefee`** puede dejar la recompensa
subcolateralizada. **No es una garantía de rentabilidad.** El valor esperado real
del retador es una decisión económica suya, no del protocolo:

```
expectedNet = p · reward − (1 − p) · deposit − gasCost
```

donde `p` es la probabilidad, según su propia creencia, de que el challenge
triunfe. `p` **no** entra al contrato.

## Tiempos

Las ventanas de revelación se miden en **bloques**; su duración en tiempo es
**nominal** y depende del tiempo de bloque de la red.

- Monad documenta actualmente **~300 ms por bloque**.
- `REVEAL_WINDOW_BLOCKS = 7200` → **~36 minutos nominales**.
- `REVEAL_DELAY_BLOCKS = 5` → ~1,5 s nominales.
- Nunca hay que prometer una duración exacta para una ventana expresada en
  bloques.
- `MIN_WINDOW` **sí** está en segundos (1 hora): es la ventana mínima para sellar.

Fuentes: <https://docs.monad.xyz/developer-essentials/summary> ·
<https://docs.monad.xyz/developer-essentials/gas-pricing>

## Verificación de las entradas: fuera de la cadena

El contrato verifica **aritmética sobre entradas declaradas**. No verifica que las
entradas hayan ocurrido: el board, las cartas, el bote y el precio los declara el
agente y el contrato los toma como dados.

En el dominio del adaptador de póker **sí se pueden verificar por terceros y sin
credenciales**: la arena de dev.fun expone endpoints tRPC públicos.

```
https://arena.dev.fun/api/arena.getTexasReplay?input={"json":{"tableId":"..."}}
```

Con `tableId` y `sequence`, cualquiera baja el replay y comprueba a mano que las
cartas, el board, el bote y el precio del compromiso son los de ahí. Es una
verificación de **terceros, no de la cadena**, y depende de que dev.fun siga
sirviendo esos endpoints.

## Los límites declarados del dominio de póker

No son pendientes; son lo que este diseño no puede hacer. En resumen: (1) que las
entradas sean verdad; (2) que el tier de la evidencia sea el correcto (el retador
elige uno de tres, no manos sueltas); (3) que el recomputer sea determinista
(`view` puede leer estado); (4) que la acción declarada se haya seguido del valor;
(5) que la tabla `_VR_MIX` del modelo sea correcta (medida sobre showdowns, con
sesgo documentado); (6) Sybil entre agente y retador. Un challenge exitoso muestra
que el número da distinto con otro tier, no que el número nuevo sea el bueno.

## El puente: de una mano real a los bytes

`bridge/` convierte una decisión concreta de una mesa real en los bytes exactos
que espera `DissentCore.commit`, y muestra los argumentos de `commit()` en orden.
**Solo biblioteca estándar de Python.** `keccak256` y la codificación ABI están a
mano y comprobados contra `cast`; `python bridge/mano.py` corre ese autochequeo.

```bash
# armar los bytes y los argumentos usando la fixture minima del caso
python bridge/armar_commit.py cmtr0ktvzxa5q15he4ekev8ub 29 --replay bridge/fixtures/alnitak-river-minimal.json

# comprobar que unos bytes son esa mano, bajando el replay del endpoint público
python bridge/verificar.py 0x0000...0e2d cmtr0ktvzxa5q15he4ekev8ub
```

`armar_commit.py` imprime `inputs`, `inputsLength`, `inputsHash`, la evidencia que
espera el adaptador (`abi.encode(uint256 tier)`, 32 bytes), y los límites de gas
recomendados para Alnitak (`recomputeGasLimit = 20_000_000`,
`validateGasLimit = 100_000`, `maxEvidenceLen = 32`). La **recompensa mínima** que
muestra es un **cálculo offline orientativo a 100 gwei**: la autoridad es
`minGasBackedReward(...)` leído del contrato justo antes del commit, y si
`block.basefee` subió, manda el resultado onchain. `reward` es `msg.value`, no un
argumento. `verificar.py` no cambia: sigue verificando solo los inputs.

Integración para otros equipos: **[`docs/INTEGRATION.md`](docs/INTEGRATION.md)**.

## Interfaz de la demo

`web/` presenta la ejecución real documentada en [`docs/LIVE_DEMO.md`](docs/LIVE_DEMO.md)
y consulta Monad testnet al cargar. No usa backend, wallet ni dependencias de
JavaScript. Verifica los cuatro recibos, el estado `Challenged`, el crédito ya
retirado y el escrow final en cero.

```powershell
node web/serve.mjs
```

Abrir `http://127.0.0.1:4173`. Instrucciones y alcance exacto:
[`web/README.md`](web/README.md).

## Correr todo

```bash
forge build
forge test                 # la suite actual (el número de tests puede cambiar)
forge lint
forge build --sizes

# calibración de gas (opt-in): reproduce las constantes del modelo de gas
forge test --match-contract GasModelCalibrationTest -vv

# tests offline del puente (sin red ni credenciales)
python -m unittest discover bridge -p "test_*.py"
python bridge/mano.py
```

Todo corre sin red, sin claves y sin desplegar nada.
