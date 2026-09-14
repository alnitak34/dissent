# Primera demo onchain — Monad testnet

Este recorrido usa los contratos registrados en [`DEPLOYMENT.md`](DEPLOYMENT.md)
y la mano pública `cmtr0ktvzxa5q15he4ekev8ub`, secuencia 29.

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
