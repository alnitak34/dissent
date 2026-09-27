# Ejecución funcional completa — Monad Mainnet

Estado: **completada y leída de vuelta desde Monad Mainnet el 2026-09-27**.
Este registro cubre `commit → seal → reveal → withdraw` para la política
Alnitak River Safety v1. Todos los recibos devolvieron `status = 1`.

Esto demuestra el funcionamiento del recorrido registrado. No demuestra
adopción externa, ausencia de otros fallos, corrección universal de la política
ni auditoría independiente.

## Identidad del despliegue

| Elemento | Valor |
| --- | --- |
| Red | Monad Mainnet, chain ID `143` |
| `DissentCore` | [`0x9D673a8B5EfE76D42593b45972Fa0426648967E1`](https://monadvision.com/address/0x9D673a8B5EfE76D42593b45972Fa0426648967E1) |
| `RecomputerRegistry` | [`0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38`](https://monadvision.com/address/0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38) |
| Recomputer | [`0x6dCD184c9c0db42FCD0De731F9a2855b38916758`](https://monadvision.com/address/0x6dCD184c9c0db42FCD0De731F9a2855b38916758) |
| Policy ID | `0xd98b72f99b52f0ac912f4a6278b95ba01a1d045bf1840f58b8a77708ca61abbc` |
| Commitment ID | `0xdd6e1e25ce02dd6cad370597156da960921d4eb671d50022ab0083f31391cccb` |
| Agente | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| Challenger | `0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02` |

## Recibos

Los costes se calculan como `receipt.gasUsed × receipt.effectiveGasPrice`.

| Fase | Transacción | Bloque | Gas del recibo | Precio efectivo | Coste |
| --- | --- | ---: | ---: | ---: | ---: |
| Commit, reward `3 MON` | [`0x59c55b…476dd0`](https://monadvision.com/tx/0x59c55bd184635cae41d2f00a56b90b5f5da07e12edef60f2642d727f0c476dd0) | 108,439,200 | 487,434 | 102 gwei | 0.049718268 MON |
| Seal, deposit `0.1 MON` | [`0x17e815…321cf0`](https://monadvision.com/tx/0x17e815f3f6ac6781e7981665ca741e92847a4a301771100dae15269b22321cf0) | 108,440,776 | 170,559 | 102 gwei | 0.017397018 MON |
| Reveal exitoso | [`0xbc121f…a4f529`](https://monadvision.com/tx/0xbc121f84234ec22fc8aace845333e3b4e169c2f55776fa55f967d70317a4f529) | 108,441,453 | 30,000,000 | 102 gwei | 3.060000000 MON |
| Retiro de `3.1 MON` | [`0xf2378b…f8e336`](https://monadvision.com/tx/0xf2378b1d2b3bb6420c0894c6d760576c35adb393bc71d0fce69852a4ddf8e336) | 108,442,607 | 107,829 | 102 gwei | 0.010998558 MON |
| **Total gas** |  |  | **30,765,822** |  | **3.138113844 MON** |

## Resultado del protocolo

- El valor base calculado al commit fue `0`.
- La política comprometida afirmaba `violation <= 0`.
- La evidencia permitida produjo `violation = 1`.
- `ChallengeSucceeded` acreditó `3.1 MON` al challenger: recompensa de `3 MON`
  más devolución del depósito de `0.1 MON`.
- El commitment terminó en `Status.Challenged`.
- El sello terminó con `settled = true`.
- Después del retiro: `credits(challenger) = 0`, `escrowed = 0` y balance del
  core `= 0 MON`.

La sal del challenger se guardó cifrada localmente hasta el reveal y se eliminó
después del retiro. No se añadió a Git.

## Resultado económico medido

| Concepto del challenger | MON |
| --- | ---: |
| Saldo antes del sello | 6.000000000 |
| Gas de seal + reveal + withdraw | -3.088395576 |
| Recompensa recibida | +3.000000000 |
| Depósito | devuelto; efecto neto 0 |
| Saldo final | 5.911604424 |
| **Resultado neto medido** | **-0.088395576** |

Por tanto, la recompensa de `3 MON` **no cubrió completamente el gas de este
recorrido operativo**, aunque el desafío y el pago funcionaron. Esto es
coherente con la documentación del contrato: `MIN_GAS_BACKED_REWARD` cubre el
presupuesto de referencia del protocolo, no cualquier gas limit que declare la
transacción ni garantiza rentabilidad.

## Hallazgo operativo de gas

Antes del commit, el core devolvió:

```text
txRequired              = 20,972,966 gas
minGasBackedReward      = 2.1172966 MON
reward elegida          = 3 MON
```

El reveal no se simuló contra el RPC con la sal real antes del broadcast, para
no exponerla antes de publicar. Se transmitió con `--skip-simulation`. La
transacción firmada declaró `gasLimit = 30,000,000`; el recibo también registró
`gasUsed = 30,000,000`. Su `maxFeePerGas` firmado fue `145 gwei`, su prioridad
`2 gwei` y su precio efectivo `102 gwei`.

Este recibo prueba el coste de **esa transacción**, pero no prueba que la
recomputación necesitara 30M de gas computacional. El recorrido Testnet previo
había sido incluido con un límite menor. Antes de otra campaña Mainnet hay que
construir y validar una ruta de envío que fije un límite de transacción acotado,
sin revelar la sal antes de tiempo, y volver a medir la economía. No se debe
subir la recompensa ni cambiar el core basándose únicamente en una estimación.

## Límites de la evidencia

- La fuente verificada demuestra coincidencia de bytecode, no seguridad.
- El recomputer define la semántica de la política; DissentCore define la
  mecánica del desafío.
- El caso usa una política de póker concreta y un estado histórico permitido.
- No existe todavía una integración independiente ni una auditoría externa.
- El resultado económico es una medición histórica, no una cotización futura.
