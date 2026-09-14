# Primera demo onchain — Monad testnet

Este recorrido usa los contratos registrados en [`DEPLOYMENT.md`](DEPLOYMENT.md)
y la mano pública `cmtr0ktvzxa5q15he4ekev8ub`, secuencia 29.

La mano fue jugada por Alnitak en dev.fun Arena. Dissent es un proyecto
independiente y no está respaldado ni afiliado a dev.fun. El uso y la posible
redistribución del replay completo se revisan por separado; esta atribución no se
presenta como autorización de dev.fun.

## Cuentas y valores fijados

| Rol | Dirección |
|---|---|
| Agente | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| Challenger | `0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02` |

- Reward: 3 MON de testnet.
- Depósito del challenger: 0.1 MON de testnet.
- Ventana para sellar: 1 hora.
- Evidencia: tier 2 (`OVERBET`), codificado como `abi.encode(uint256(2))`.
- Resultado esperado: el valor baja de `0.685725947521865889` a
  `0.177000000000000000`, cruza el umbral `0.362900000000000000` y el
  commitment termina `Challenged`.

El resultado esperado sale de `test/ManoReal.t.sol`. La ejecución real debe
confirmarse con eventos, estado y saldos onchain; no se da por cierta por el test.

## Reglas operativas

1. Cada operación se simula sin `--broadcast` antes de firmarse.
2. Rabby debe mostrar Monad Testnet, chain id 10143, y la cuenta del rol indicado.
3. El salt del challenger es secreto hasta el reveal. No se guarda en Git, no se
   pega en chats y no se imprime. Con tres tiers posibles, un salt público haría
   trivial adivinar la evidencia a partir del sello.
4. El `DISSENT_COMMITMENT_ID` usado en challenge debe salir del evento `Committed`
   del recibo real. El ID impreso durante la simulación no es autoridad porque el
   timestamp del bloque puede cambiar.
5. Después de `challengeCommit`, no se cierra la terminal que contiene el salt
   hasta terminar `challengeReveal`.

## Scripts

`script/DemoFlow.s.sol` contiene cuatro operaciones independientes:

- `DemoCommit`: el agente abre el commitment.
- `DemoChallengeCommit`: el challenger sella tier 2.
- `DemoChallengeReveal`: revela y exige que el caso sea refutatorio antes de
  transmitir.
- `DemoWithdraw`: el challenger retira el crédito después del éxito.

También contiene tres operaciones de recuperación para un recorrido vencido:

- `DemoSweepExpired`: liquida el sello no revelado y acredita su depósito al agente.
- `DemoReclaim`: acredita al agente la recompensa de un commitment no refutado.
- `DemoWithdrawAgent`: retira a la wallet agente los créditos acumulados.

Las operaciones de recuperación existen para registrar y cerrar un recorrido
fallido; no convierten `Reclaimed` en una verificación de la afirmación.

Los comandos exactos se ejecutan uno por uno y se registran con sus recibos. No se
encadenan: ninguna operación posterior se prepara hasta verificar onchain la
anterior.

## Ejecución completa confirmada — 14 de septiembre de 2026

La segunda ejecución completó el ciclo entero en Monad testnet. Todos los recibos
devuelven `status = 1` y apuntan al `DissentCore` desplegado en
`0x6dCD184c9c0db42FCD0De731F9a2855b38916758`.

- Commitment ID:
  `0xd8c13c6574b6c3af196154a835a93a03bcf7ffe9e4212c2fb81f8c21d5e22811`.

| Paso | Transacción | Bloque | Gas usado | Resultado comprobado |
|---|---|---:|---:|---|
| Agente abre el commitment | [`0xc2215f…04f5f`](https://testnet.monadvision.com/tx/0xc2215f552c299527154055fc9e706b5fe0d5e9ddf387d9ff5c8670bf52304f5f) | 62.466.248 | 26.829.863 | 3 MON quedan en escrow. |
| Challenger sella tier 2 | [`0x593b6b…dad6d8`](https://testnet.monadvision.com/tx/0x593b6badea3209085196e3ac3b7d1a8b81f8c14f64e197e3d39e7c5d06dad6d8) | 62.467.545 | 170.661 | Sello registrado con depósito de 0,1 MON. |
| Challenger revela | [`0x427b5c…1e188e`](https://testnet.monadvision.com/tx/0x427b5ca4e64453bf00591a364c8a0fe9d91cafffa67a4af1a520fe1f8d1e188e) | 62.471.460 | 23.272.595 | La evidencia cruza el umbral; estado `Challenged`; se acreditan 3,1 MON al challenger. |
| Challenger retira | [`0x621151…c7c61f`](https://testnet.monadvision.com/tx/0x621151e057ceb3e52d8febf2e1e91eba77fbd5f9a901eb586d62d0fe4fc7c61f) | 62.472.289 | 93.421 | `withdrawCredit()` entrega los 3,1 MON. |

Lecturas de cierre contra el RPC público después del retiro:

- `credits(challenger) = 0`.
- `escrowed() = 0`.
- balance de `DissentCore = 0`.

Esto demuestra un caso concreto, no una auditoría general: el agente comprometió
una afirmación, un tercero ocultó y luego reveló evidencia, el recomputer produjo
el nuevo valor onchain, el umbral quedó refutado y el contrato liquidó y permitió
retirar el pago sin intervención administrativa.
