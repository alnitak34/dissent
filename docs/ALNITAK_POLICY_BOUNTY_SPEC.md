# Especificación candidata — Alnitak River Safety Gate v1

Estado: **adaptador desplegado y recorrido funcional ejecutado en Monad
Testnet; validación de demanda pendiente**. La regla y el
contraejemplo proceden del código y de mediciones de Alnitak. El verificador
independiente y el recomputer Solidity coinciden en fixtures y vectores de
regresión; el flujo completo pasa localmente. El exportador recorrió 2.184
replays históricos, reconstruyó 11 estados elegibles y encontró tres
contraejemplos. La medición es retrospectiva, no prospectiva. Todavía falta
validar demanda externa.

## Afirmación falsable

> Para todo estado válido del dominio, si `Alnitak River Safety Gate v1`
> autoriza una llamada bajo presión, la equity exacta condicionada por esa
> presión es al menos `pot price + 15 puntos porcentuales`.

Una campaña cubre una versión del gate. No se abre una recompensa por mano.

## Qué representa v1

`v1` es la versión histórica que autorizaba el escape usando el modelo de rango
anterior. El recomputer no necesita portar las aproximadamente 1.400 líneas del
agente: solo las dos funciones necesarias para juzgar esta afirmación:

1. el gate anterior, que decide si la llamada quedaba autorizada;
2. el cálculo exacto condicionado por la presión observada, que decide si el
   margen prometido realmente se cumplía.

La identidad del compromiso debe incluir el hash del código o de una
especificación canónica de esas dos funciones. No debe llamarse auditoría de todo
Alnitak.

## Dominio válido candidato

Un estado solo es admisible si cumple todo lo siguiente:

- es river heads-up: dos cartas propias, cinco comunitarias y un rival activo;
- las siete cartas son válidas y no se repiten;
- existe una cantidad positiva por pagar y un bote anterior positivo;
- la traza mínima de acciones permite derivar, no declarar libremente, una de
  las cuatro clases de presión ya registradas por Alnitak:
  `bet/big`, `multi/small`, `multi/big` o `raise/any`;
- el precio se calcula desde bote y cantidad por pagar;
- el margen es `0.15`, tomado de `_POT_ODDS_MARGIN`;
- las mezclas y la frontera de tamaño son las de `_VR_MIX` en la versión
  `84dbf79` del repositorio del bot.

No se aceptan como evidencia el resultado de la mano, las cartas reales del
rival ni una etiqueta de presión enviada sin la traza que permite recalcularla.

## Evidencia candidata

```text
hole cards
board cards
pot facing the agent before its call
amount to call
minimal ordered aggressive-action trace
```

`validateEvidence` debe comprobar formato, cartas, cantidades, orden de la traza
y pertenencia al dominio. El challenger no aporta equities ni el veredicto.

## ABI candidato

Estado: **diseño por implementar y medir**, no interfaz desplegada.

```solidity
struct PolicyInputs {
    bytes32 policySpecHash;       // hash del texto canónico de esta garantía
    bytes20 originCommit;         // commit Git del que se derivó la regla v1
    uint16 marginBp;              // exactamente 1500 para v1
}

struct Counterexample {
    bytes7 cards;                 // 2 hole + 5 board, rank*4+suit (8..59)
    uint64 potFacingDecision;     // bote visible antes de la llamada del agente
    uint64 callAmount;
    bytes8 aggressiveTrace;       // hasta 8 eventos compactos y ordenados
    uint8 traceLength;
}
```

Cada byte de `aggressiveTrace` codifica calle, actor y acción
(`bet`/`raise`/`all-in`). El adaptador debe rechazar bits reservados, eventos
fuera de orden, actores desconocidos y cualquier traza cuyo último evento no sea
agresión del rival en river. La clase de presión se deriva dentro del adaptador:

- último evento `raise` o `all-in` → `raise/any`;
- en otro caso, agresión del rival en dos o más calles → `multi`;
- una sola calle → `bet`;
- `big` solo cuando `callAmount / (potFacingDecision - callAmount) > 65%`.

No se incluyen `pressure`, `mixBp`, equity ni resultado económico en la
evidencia. Aceptarlos del challenger permitiría elegir parte del veredicto.

El compromiso de Dissent ya ata la dirección exacta del recomputer. El
`policySpecHash` añade una referencia legible y portable a la garantía, y
`originCommit` identifica el código histórico del que se derivó la política:
`e6a7e49857602ac84257dc78f0960506f87cd7f3`. No afirma que el adaptador ejecute
byte por byte aquel código: esa versión todavía estimaba equity mediante
muestreo. La autoridad determinista es la especificación canónica y su hash; no
se usarán ceros ni placeholders en la demo final.

La versión canónica está en
`docs/policies/alnitak-river-safety-v1.json`. Serializada como JSON UTF-8 con
claves ordenadas y sin espacios, `bridge/policy_spec.py` reproduce su keccak256.
Sus tests fijan el hash y comprueban que
las cuatro mezclas usadas por el verificador independiente coincidan con el
documento canónico.

```text
policySpecHash = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0
```

## Veredicto determinista

```text
threshold = potPrice + 0.15
oldEquity = exact value of the v1 range model
conditionedEquity = exact value under the derived pressure mix

violation = oldEquity >= threshold
         && conditionedEquity < threshold
```

La primera condición demuestra que el gate v1 habría autorizado la llamada. La
segunda demuestra que la misma llamada no cumplía la garantía robusta publicada.
El recomputer devuelve `1` cuando ambas se cumplen y `0` en cualquier otro estado
válido. Con evidencia vacía devuelve `0`.

## Contraejemplo y control

Contraejemplo histórico candidato:

```text
Jh Jd | board 5c 9s 2h 6h 4c
old exact equity 56.8942% | conditioned exact equity 32.0046%
pot price 27.4170% | required 42.4170%
v1 authorizes | robust gate rejects
```

Control positivo histórico del mismo dominio de river:

```text
4h Ah | board Ac 3h 6d Th 8c
old exact equity 73.0375% | conditioned exact equity 77.2441%
pot price 25.0000% | required 40.0000%
both versions call
```

Los porcentajes históricos redondeados procedían del muestreo anterior. Las
cifras de esta tabla proceden de `bridge/policy_bounty.py`, un verificador exacto
que no importa el bot, el bridge existente ni Solidity. Las fixtures mínimas
están en `bridge/fixtures/`. El valor condicionado coincide además con el
`AlnitakRiverRecomputer` desplegado en Monad Testnet para ambos casos.

## Qué prueba y qué no

Prueba, si se implementa correctamente, que existe un estado permitido que rompe
una propiedad concreta de un componente concreto de una versión concreta.

No prueba que:

- Alnitak sea seguro en general;
- una política sin challenges sea segura;
- el modelo de presión sea la verdad sobre un rival;
- el resultado económico de una mano determine la calidad de la decisión;
- Dissent sustituya una auditoría o un guard de ejecución.

## Estado de las puertas

1. **Fixtures y verificador independiente — cerrado localmente:** `JhJd` rompe
   la regla, `4hAh` es control, y cambios de resultado, precio, cartas o traza no
   pueden fabricar el mismo veredicto.
2. **Identidad y ABI — cerrado como prototipo:** política canónica con hash,
   origen histórico y evidencia fija de 160 bytes.
3. **IRecomputer — desplegado en Monad Testnet:**
   `AlnitakPolicyBountyRecomputer` no modifica `DissentCore`; su bytecode y sus
   constantes se comprobaron onchain después del despliegue.
4. **Gas — cerrado para este recorrido:** recompute medido en 17.141.001
   gas; reveal completo en 17.267.473. Con `R=20M`, `V=100k`, inputs de 96 B y
   evidencia de 160 B, Dissent calcula `txRequired=20.972.966` y recompensa
   mínima de referencia `2,1172966 MON` a 100 gwei. El reveal real declaró y
   pagó 22.211.703 gas en Monad Testnet, bajo el límite de 30M. El detalle está
   en `docs/POLICY_BOUNTY_LIVE_RUN.md`.
5. **Búsqueda histórica — cerrada, validación prospectiva pendiente:**
   `exportar_policy_bounty.py` recorrió 2.184 replays, reconstruyó 11 estados
   elegibles y encontró tres violaciones sin recibir sus ids como ganadores. La
   política se diseñó después de observar parte de este historial; por tanto,
   falta congelarla y reportar resultados sobre replays posteriores no usados en
   el diseño. Ver [`HISTORICAL_CORPUS_AUDIT.md`](HISTORICAL_CORPUS_AUDIT.md).
6. **Demanda — abierta:** preguntar a un constructor externo si financiaría una campaña equivalente
   sobre una regla propia. Sin una respuesta, el valor de mercado sigue siendo
   hipótesis.
