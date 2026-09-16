# Prueba de AdapterFault en Monad Testnet

Estado: adaptador de prueba y commit desplegados en Monad Testnet el
2026-09-16; **sello y reveal todavia no ejecutados onchain**.

Objetivo limitado: comprobar con recibos reales que un adaptador que funciona al
crear la campaña pero revierte al revelar produce `Status.Faulted`, devuelve el
deposito al retador y la recompensa al agente, y no paga un bounty. Esto no es
una auditoria del protocolo ni una prueba de seguridad general.

## Piezas

- `script/DeployFaultProbe.s.sol`: adaptador deliberadamente fallido, SOLO testnet.
- `script/FaultProbeFlow.s.sol`: fases separadas `FaultProbeCommit`,
  `FaultProbeSeal` y `FaultProbeReveal`. Cada fase envia como maximo una
  transaccion, y solo con `--broadcast`.
- `test/FaultProbeFlow.t.sol`: recorre el ciclo con retiro de ambos creditos.

El Core es el ya desplegado en Testnet:
`0x460f9F624da9e23c705c610E1263bf3641bCce23`. Los scripts rechazan otra
cadena y otra cuenta de firma. Tras desplegar el probe, las fases posteriores
comprueban su runtime bytecode exacto, no solo su nombre o dominio.

## Despliegue confirmado

| Campo | Valor |
|---|---|
| FaultProbeRecomputer | `0xda0eff9269f555529ce7c87e840cf19b67e9ce5d` |
| Transaccion | `0x3876ed28e23f668d073f6b60aafe7c1a8a61c0fcbe4c7343dd101055fe890bed` |
| Bloque | `63070079` |
| Recibo | `status = 1` |
| Gas cobrado | `221.603` a `203,847222222` gwei |
| Coste real | `0,045173155986061866` test MON |
| Bytecode | 432 bytes; coincide exactamente con el runtime compilado local |

El dry-run con la cuenta real habia estimado 192.055 gas y
`0,03914987826384621` test MON. Fue **inferior al recibo real**; la diferencia
fue `29.548` gas y `0,006023277722215656` test MON. No se debe usar esa
simulacion como coste pagado. No hubo transferencia de recompensa ni deposito
en esta transaccion: fue solo creacion del adaptador.

## Commit confirmado

| Campo | Valor |
|---|---|
| Commitment id real | `0x8e070ccf60c67444a4af4205a4e2edc7c4530480320754fe3c3b412a2b4dd3ca` |
| Transaccion | `0x3dbaa96871af96bc2c0f1c658b5ee2f0e979441d3c13ab5c62450aa2f8fb5a0e` |
| Bloque | `63071793` |
| Recibo | `status = 1` |
| Gas cobrado | `452.906` a `203,000000001` gwei |
| Coste real de gas | `0,091939918000452906` test MON |
| Recompensa escrowada | `0,25` test MON |
| Deposito exigido al retador | `0,01` test MON |
| WindowEnds | `2026-09-16 17:04:26 UTC` |
| Lectura onchain | `Status.Open`; agente y recomputer coinciden con los esperados |

El dry-run del commit habia estimado 392.518 gas y
`0,079681154000392518` test MON; otra vez subestimo el cobro real. El ID
simulado NO fue el real porque `windowEnds` depende del timestamp del bloque.
El ID de arriba proviene del evento `Committed` y se verifico leyendo
`getCommitment` directamente del contrato. Si nadie sella antes de
`windowEnds`, la recompensa no se pierde automaticamente: el agente debera
ejecutar `reclaim` cuando lo permita el contrato y pagar gas para recuperarla.

## Fondos y riesgo ANTES de firmar

- El agente inmoviliza `0,25` test MON de recompensa. El retador inmoviliza
  `0,01` test MON de deposito. En el camino esperado, ambos recuperan su
  principal via credito y `withdrawCredit()`; esas retiradas tambien consumen gas.
- El gas gastado no se recupera. Si el retador no revela dentro de la ventana,
  puede perder el deposito. Si una fase revierte, tambien paga el gas cobrado.
- En la consulta de preflight del 2026-09-16, el contrato calculo
  `minGasBackedReward(100000,1000000,32,32) = 0,1867025` test MON y
  `txRequired(...) = 1.667.025` gas. Son valores de esa consulta, no promesa de
  coste final ni garantia de rentabilidad.
- El despliegue ya costo `0,045173155986061866` test MON (recibo arriba).
  Los otros pasos aun no tienen estimacion RPC sobre el probe desplegado;
  no se debe presentar ese numero como coste total.

## Orden operativo

1. HECHO: revisar `git status`, saldos, chain id y gas. Simular el despliegue
   SIN `--broadcast`:

   `forge script script/DeployFaultProbe.s.sol:DeployFaultProbe --rpc-url https://testnet-rpc.monad.xyz`

2. HECHO: desplegar el probe y verificar recibo, direccion y bytecode. La
   direccion impresa en el dry-run NO fue la autoridad; si coincide con la
   real, es porque se uso el mismo sender y nonce.
3. HECHO: ejecutar y verificar el commit del agente. PENDIENTE: simular y
   ejecutar por separado sello del retador y reveal, verificando cada recibo
   antes del siguiente. Los salts se generan y
   guardan fuera de Git; **nunca se pegan en un chat ni se imprimen**.
4. Leer `status`, `credits(agent)`, `credits(challenger)` y `escrowed()` onchain.
   Si el resultado es el esperado, cada beneficiario retira su propio credito.

No usar el antiguo DissentCore de Testnet: su politica de `AdapterFault` era
distinta. No realizar esta prueba en Mainnet.
