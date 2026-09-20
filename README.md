# Dissent — apuestas sobre afirmaciones deterministas

Dissent es un protocolo en Monad para afirmaciones numéricas **falsables**.

En términos de producto: **un bug bounty para decisiones de agentes**. El
agente pone una recompensa detrás de un límite numérico; challengers buscan un
contraejemplo dentro del espacio que define el recomputer, y Monad paga si ese
caso cruza el límite.

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

Hay **dos versiones distintas** en Monad Testnet:

- **Policy Bounty, despliegue del 16-09-2026:**
  [`DissentCore 0x460f...ce23`](https://testnet.monadvision.com/address/0x460f9F624da9e23c705c610E1263bf3641bCce23)
  y [`AlnitakPolicyBountyRecomputer 0x10EE...Cb2d`](https://testnet.monadvision.com/address/0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d).
  Este núcleo implementa la regla nueva: un `AdapterFault` devuelve el depósito
  al retador y la recompensa al agente; **no paga bounty por un fallo técnico**.
  Una refutación válida y los retiros se ejecutaron en testnet; los siete
  recibos, el compromiso y el estado final están en
  [`docs/POLICY_BOUNTY_LIVE_RUN.md`](docs/POLICY_BOUNTY_LIVE_RUN.md). Un
  adaptador de prueba que revierte en `recompute` también produjo
  `Status.Faulted` onchain, sin bounty: recibo y créditos en
  [`docs/FAULT_PROBE.md`](docs/FAULT_PROBE.md).
- **Versión anterior, histórica:**
  [`DissentCore 0x6dCD...6758`](https://testnet.monadvision.com/address/0x6dCD184c9c0db42FCD0De731F9a2855b38916758)
  y [`AlnitakRiverRecomputer 0x2a26...8E38`](https://testnet.monadvision.com/address/0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38).
  Su `AdapterFault` sí pagaba al retador; no debe confundirse con la versión
  nueva. Recibos y verificación de esta versión:
  [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

La ruta `AdapterFault` nueva está cubierta por pruebas locales/CI y por **una
ejecución concreta en Monad Testnet** con un adaptador deliberadamente fallido;
esto no valida todos los posibles fallos. El 16-09-2026,
ambas fuentes se verificaron con `Status: match` en Sourcify y MonadVision ya
muestra **«Contract Source Code Verified»** para los dos contratos nuevos
(enlaces arriba). La verificación de fuente **no es una auditoría externa**;
esta sigue pendiente. La rama de seguridad se fusionó a `master` el 20-09-2026
mediante el PR #1 (merge commit `5cd68f4`), y la página pública en Vercel muestra
el replay verificable de Policy Bounty.

Hay dos adaptadores de póker, puentes en Python y una interfaz web de solo
lectura que comprueba la ejecución de Policy Bounty contra el RPC público. La
indexación general de commitments y la escritura desde una wallet siguen
siendo trabajo futuro.

## Estructura de `src/`

| Archivo | Qué es |
|---|---|
| `src/IRecomputer.sol` | La frontera entre el protocolo y el dominio. Una sola función de valor. |
| `src/DissentCore.sol` | El protocolo. No sabe de póker. Sin owner, sin retiro administrativo del escrow, sin pausa y sin proxy. Los beneficiarios retiran sus propios créditos con `withdrawCredit()`. |
| `src/adapters/AlnitakRiverRecomputer.sol` | Adaptador de póker de ejemplo, port de `_exact_river_mix()` de `strategy.py`. |
| `src/adapters/AlnitakPolicyBountyRecomputer.sol` | Adaptador de la campaña de política v1; recibe un estado completo como contraejemplo. |
| `src/adapters/PokerEval.sol` | Evaluador de manos de 7 cartas, usado por ambos adaptadores de póker. |

`src/` fuera de `adapters/` es solo el protocolo y la frontera: nada de un
dominio concreto vive ahí.

## Tabla de resultados de un challenge

| Estado / evento | Cuándo | Depósito | Recompensa | Significado |
|---|---|---|---|---|
| **Challenged** | evidencia válida y `recompute` **cruza** el umbral | vuelve al retador (dentro del payout) | al retador | la afirmación fue refutada con esa evidencia |
| **ChallengeFailed** | evidencia válida y `recompute` **no cruza**; sigue `Open` | al agente | — | la afirmación se sostuvo frente a esa evidencia |
| **ChallengeRejected** | `validateEvidence` devolvió `false` canónico; sello liquidado; sigue `Open` | **vuelve al retador** | — | evidencia malformada: **inconcluso**, el agente no cosecha |
| **Faulted** | el adaptador revirtió, hizo OOG, o devolvió ABI no canónico **teniendo el gas prometido** | vuelve al retador | vuelve al agente | **campaña inválida por fallo técnico**; NO es una refutación y NO paga bounty |
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
  `block.timestamp`, `block.basefee`, storage persistente o storage transitorio
  (`TLOAD`), y comportarse distinto según el contexto. `STATICCALL` impide
  escribir con `TSTORE`, pero no impide leer un valor transitorio preparado por
  otra llamada al mismo adaptador durante la misma transacción.
- `domain()` es una **etiqueta**, no una prueba de honestidad.
- Un **proxy** o un adaptador con storage mutable puede **cambiar de
  comportamiento** después de que se creen compromisos contra él.
- Los resultados **valen tanto como el adaptador**. Dissent **no es un oráculo de
  verdad**.
- Un agente malicioso todavía puede elegir un adaptador que falle durante el
  challenge para evitar una refutación pagable. La campaña queda públicamente
  `Faulted`, el retador recupera su depósito y la recompensa vuelve al agente;
  el retador sigue soportando el gas. El MVP no tiene árbitro ni gobernanza para
  decidir quién causó un fallo técnico.
- **Para producción**, el consumidor debe exigir adaptadores **auditados,
  inmutables, con fuente verificada y versión reconocible** (`domain()`), y tratar
  un adaptador desconocido como no confiable. También debe rechazar adaptadores
  cuyo resultado dependa del contexto EVM o de estado transitorio externo a los
  `inputs` y la `evidence` comprometidos.

Contadores como "cuántos `ChallengeRejected` o `AdapterFaulted` acumuló un
compromiso" se **derivan indexando eventos**; el núcleo **no** los almacena.

La decisión de no pagar por fallos técnicos, su amenaza de origen y los casos
todavía pendientes están en
[`docs/SECURITY_DECISION_ADAPTER_FAULT.md`](docs/SECURITY_DECISION_ADAPTER_FAULT.md).
Para una revisión independiente, las invariantes, límites conocidos y preguntas
prioritarias están en
[`docs/EXTERNAL_REVIEW_REQUEST.md`](docs/EXTERNAL_REVIEW_REQUEST.md).

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

## Adaptador anterior de mano fija: alcance y límites

Esta sección y el puente `armar_commit.py` describen
`AlnitakRiverRecomputer`, usado en la primera demo; **no** describen el
espacio de evidencia de `AlnitakPolicyBountyRecomputer` ni su campaña actual.

### Verificación de las entradas: fuera de la cadena

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

### Los límites declarados de la demo de mano fija

No son pendientes; son lo que este diseño no puede hacer. En resumen: (1) que las
entradas sean verdad; (2) que el tier de la evidencia sea el correcto (el retador
elige uno de tres, no manos sueltas); (3) que el recomputer sea determinista
(`view` puede leer estado); (4) que la acción declarada se haya seguido del valor;
(5) que la tabla `_VR_MIX` del modelo sea correcta (medida sobre showdowns, con
sesgo documentado); (6) Sybil entre agente y retador. Un challenge exitoso muestra
que el número da distinto con otro tier, no que el número nuevo sea el bueno.

`AlnitakRiverRecomputer` tiene solo tres tiers. Por eso demuestra de extremo a
extremo la mecánica de Dissent, pero no demuestra todavía el valor comercial de
una búsqueda abierta: el propio agente podría agotar esos tres casos. Un caso de
mercado necesita un espacio de contraejemplos suficientemente grande o
especializado para que encontrar uno tenga valor.

### El puente anterior: de una mano real a los bytes

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

## Campaña Policy Bounty v1

Integración para otros equipos: **[`docs/INTEGRATION.md`](docs/INTEGRATION.md)**.

El bounty sobre una versión completa de política usa un puente separado. Este
produce los `inputs` de 96 bytes y la evidencia de 160 bytes que espera
`AlnitakPolicyBountyRecomputer`, sin firmas, wallet ni hex escrito a mano.

Este segundo adaptador está desplegado con el núcleo endurecido. Su campaña
ejecutada y sus recibos corresponden a la versión **Policy Bounty**, no a la
demostración anterior de una mano fija. Ver
[`docs/POLICY_BOUNTY_LIVE_RUN.md`](docs/POLICY_BOUNTY_LIVE_RUN.md).

```bash
python bridge/armar_policy_bounty.py bridge/fixtures/policy-bounty-jhjd.json
python bridge/buscar_policy_bounty.py bridge/fixtures/policy-bounty-control-4hah.json bridge/fixtures/policy-bounty-jhjd.json
python bridge/exportar_policy_bounty.py <DIRECTORIO_DE_REPLAYS_S17> <DIRECTORIO_DE_REPLAYS_S18>
```

El tercer comando reconstruye candidatos desde replays crudos y los evalúa sin
usar el ganador ni el resultado económico. La auditoría retrospectiva local,
sus cifras y sus límites están en
[`docs/HISTORICAL_CORPUS_AUDIT.md`](docs/HISTORICAL_CORPUS_AUDIT.md).

El segundo comando no conoce cuál candidato gana: aplica el verificador a cada
JSON y reporta los contraejemplos. El corpus actual contiene solo dos fixtures;
por tanto demuestra el recorrido técnico, **no** una búsqueda amplia o difícil.

## Interfaz de la demo

`web/` presenta la ejecución de Policy Bounty documentada en
[`docs/POLICY_BOUNTY_LIVE_RUN.md`](docs/POLICY_BOUNTY_LIVE_RUN.md). Al completar
el replay consulta Monad Testnet. No usa backend, wallet ni dependencias de
JavaScript. Verifica siete recibos, el evento de refutación, el estado
`Challenged`, los dos créditos retirados y el escrow final en cero. La demo
anterior de una mano fija permanece documentada en
[`docs/LIVE_DEMO.md`](docs/LIVE_DEMO.md), pero ya no es el caso principal de la web.

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

# tests offline de la verificacion de eventos de la web
node --test web/proof.test.mjs
```

Todo corre sin red, sin claves y sin desplegar nada.
