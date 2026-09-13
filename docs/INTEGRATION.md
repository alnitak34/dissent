# Integración con Dissent

Guía para escribir un `recomputer` propio e integrar un dominio nuevo. El
protocolo (`DissentCore`) es agnóstico de dominio; todo lo específico vive detrás
de `IRecomputer`.

> Antes de nada, leé la **[Frontera de confianza](../README.md#frontera-de-confianza)**:
> el núcleo garantiza la mecánica, tu adaptador define la semántica. Un adaptador
> deshonesto o no determinista produce resultados sin valor.

## La interfaz `IRecomputer`

```solidity
interface IRecomputer {
    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256 value);
    function validateEvidence(bytes calldata inputs, bytes calldata evidence) external view returns (bool ok, bytes32 reason);
    function scale() external pure returns (uint256);
    function domain() external pure returns (bytes32);
}
```

- **`recompute(inputs, "")`** (evidencia vacía) = el **valor base**, el planteo
  completo sin restringir. Lo calcula el núcleo en el `commit` y lo guarda. No hay
  una función aparte para el base: es la misma `recompute`, para que las dos ramas
  usen idéntica aritmética.
- **`recompute(inputs, evidence)`** (evidencia no vacía) = el valor bajo la
  restricción que trae el retador.
- **`validateEvidence(inputs, evidence)`** = si la evidencia está **bien formada**
  para estos inputs. Devolver `(false, reason)` de forma canónica es una respuesta
  legítima ("evidencia malformada"), no un fallo: produce `ChallengeRejected`, se
  liquida el sello y **se le devuelve el depósito al retador**.
- **`scale()`** = la unidad del valor (1e18 para WAD, 1e4 para bp, 1 para enteros).
  El núcleo la exige distinta de cero y la emite; no la usa para calcular.
- **`domain()`** = etiqueta de identidad/versión del modelo. El núcleo la guarda y
  reemite. Es una etiqueta, no una prueba de honestidad.

El núcleo invoca `recompute` y `validateEvidence` por **STATICCALL** (por eso son
`view`): no pueden escribir estado ni reentrar escribiendo.

## Requisitos de retorno ABI (canónico)

El núcleo copia un tamaño **fijo** de returndata y exige que sea canónico. Si no lo
es, cuenta como **fallo técnico del adaptador** (`AdapterFault`), no como respuesta:

- **`recompute`** debe devolver **exactamente 32 bytes** (un `int256`). Cualquier
  otro tamaño → `Faulted`.
- **`validateEvidence`** debe devolver **exactamente 64 bytes**: un `bool`
  **canónico** (la primera palabra es 0 o 1) y un `bytes32 reason`. Un `bool` con
  otro valor, u otro tamaño → `Faulted`.

Devolver un returndata enorme no ayuda: el núcleo solo copia 32/64 bytes.

## Elegir y medir `recomputeGasLimit` (R) y `validateGasLimit` (V)

`R` y `V` son **límites de gas que declarás en el commit** y quedan en la identidad
del compromiso (no se pueden cambiar después). Para cada llamada, el núcleo
**reserva gas suficiente para solicitar el cap declarado bajo EIP-150** (la regla
del 1/64 retenido por quien llama); el adaptador **observa algo menos** que el cap
por su propio overhead de entrada, como demuestran los probes de
`AdapterFault.t.sol` (con R=1.000.000 el adaptador observó 999.440, ~560 de
overhead). La evidencia grande **no** reduce el gas entregado.

1. Medí offline el **peor caso** de `recompute(inputs, evidence)` sobre TODAS las
   evidencias válidas de tu adaptador (no solo el base: el camino con evidencia
   puede ser más caro). Igual para `validateEvidence`.
2. Declará `R` y `V` **por encima** de esos peores casos, con margen. Si `R` queda
   corto para una evidencia honesta, ese challenge **faultea** y **el agente pierde
   la recompensa**: el incentivo te empuja a declarar suficiente.
3. El commit exige que `R` cubra al menos el `recompute` base (si no, revierte), y
   que la **transacción completa del peor caso** entre en 30M
   (`txRequired ≤ 30.000.000`).

En este repo, `test/GasModelCalibration.t.sol` muestra cómo medir estos costos de
forma reproducible con `network = "monad"`.

## Elegir `maxEvidenceLen`

Es el largo máximo de `evidence` que el compromiso acepta (≤ `MAX_EVIDENCE_LEN` del
protocolo, 128 KiB). Declaralo **igual al largo real** que tu adaptador necesita
(para Alnitak, la evidencia es `abi.encode(uint256 tier)` = **32 bytes**). Un
`maxEvidenceLen` chico y ajustado acota el peor caso de gas y el respaldo económico.

## Consultar `minGasBackedReward` antes del commit

```solidity
uint256 minReward = core.minGasBackedReward(V, R, inputs.length, maxEvidenceLen);
// enviar msg.value >= minReward
```

`minGasBackedReward = (txRequired + CHALLENGE_COMMIT_GAS) · effectiveGasPrice`,
donde `effectiveGasPrice = max(100 gwei, block.basefee)`. **Consultalo justo antes
del commit**: si `block.basefee` subió, el valor cambia, y **manda el resultado
onchain** (el `commit` revierte con `RewardBelowGasBacking` si `msg.value` es
menor). Cubre el presupuesto de gas de referencia, **no** garantiza rentabilidad
(ver la fórmula `expectedNet` en el README).

## Flujo

1. **`commit(recomputer, inputs, threshold, comparator, action, deposit, window,
   recomputeGasLimit, validateGasLimit, maxEvidenceLen, salt)`** con
   `msg.value = reward ≥ minGasBackedReward`. Devuelve el `id`.
2. El retador **`challengeCommit(id, sealedHash)`** con
   `sealedHash = keccak256(abi.encode(evidence, salt, msg.sender))`, pagando
   `deposit`.
3. **Espera** `REVEAL_DELAY_BLOCKS` (evita el front-run del reveal).
4. El retador **`challengeReveal(id, inputs, evidence, salt)`** con **suficiente
   gas** (ver `functionGasFloor`). La ventana de revelación es, según las
   comparaciones exactas del contrato, el rango de bloques **inclusivo**
   `[sealBlock + REVEAL_DELAY_BLOCKS, sealBlock + REVEAL_DELAY_BLOCKS +
   REVEAL_WINDOW_BLOCKS]`: antes del primero revierte `TooEarlyToReveal`, después
   del último revierte `RevealWindowClosed`.
5. Sin challenge exitoso al vencer la ventana, cualquiera llama **`reclaim(id)`** y
   la recompensa vuelve al agente. Un sello no revelado se barre con
   **`sweepExpiredSeal(id, challenger)`** (el depósito va al agente).

## Eventos que debería indexar una UI

- `Committed` y `CommitGasPolicy` — alta del compromiso, límites de gas, precio
  efectivo, `totalGasBacking`, `minGasBackedReward`.
- `ChallengeSealed` — un sello nuevo.
- `ChallengeSucceeded` / `ChallengeFailed` — resultado de un reveal resuelto.
- `ChallengeRejected` — evidencia malformada (inconcluso).
- `AdapterFaulted` (con `phase` = VALIDATION o RECOMPUTE) — fallo técnico del
  adaptador.
- `ChallengeVoided` — retador anulado porque otro ya resolvió.
- `SealExpired`, `Reclaimed`, `Credited`, `Withdrawn`.

Los contadores por compromiso o por adaptador (p. ej. cuántos `ChallengeRejected` o
`AdapterFaulted`) se **derivan indexando estos eventos**; el núcleo no los guarda.
Un compromiso `Reclaimed` con muchos `ChallengeRejected` es una bandera roja.

## Ejemplo mínimo de recomputer barato

```solidity
// Devuelve el valor base = inputs; con evidencia = abi.encode(int256) devuelve ese
// numero. validateEvidence acepta vacio (commit) o exactamente 32 bytes.
contract EjemploRecomputer is IRecomputer {
    function scale() external pure returns (uint256) { return 1e18; }
    function domain() external pure returns (bytes32) { return "ejemplo.v1"; }

    function validateEvidence(bytes calldata, bytes calldata evidence)
        external pure returns (bool ok, bytes32 reason)
    {
        if (evidence.length != 0 && evidence.length != 32) return (false, "BAD_LENGTH");
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence)
        external pure returns (int256)
    {
        if (evidence.length == 32) return abi.decode(evidence, (int256));
        return abi.decode(inputs, (int256));
    }
}
```

## Checklist de seguridad (para evitar un `AdapterFault` accidental)

- [ ] `recompute` devuelve **siempre exactamente 32 bytes** (`int256`), en todos
      los caminos.
- [ ] `validateEvidence` devuelve **siempre exactamente 64 bytes** con `bool`
      canónico (0 o 1).
- [ ] **Toda evidencia que `validateEvidence` acepte (`ok = true`) debe poder pasar
      por `recompute` sin revertir ni hacer OOG** dentro de `recomputeGasLimit`. Si
      `validate` acepta algo que `recompute` no puede procesar, es un `AdapterFault`
      y el agente pierde la recompensa.
- [ ] `recompute` y `validateEvidence` son **deterministas** y no dependen del
      llamador ni del contexto de bloque (o si lo hacen, entendés y aceptás las
      consecuencias de la frontera de confianza).
- [ ] `R` y `V` cubren el **peor caso medido** con margen; la evidencia más cara
      cabe en `R`.
- [ ] `maxEvidenceLen` es el mínimo que tu adaptador realmente necesita.
- [ ] El adaptador es **inmutable** (sin proxy, sin storage que cambie el
      comportamiento) si querés que los compromisos contra él sean confiables.
