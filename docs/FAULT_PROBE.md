# Prueba de AdapterFault en Monad Testnet

Estado: preparada y probada localmente; **no desplegada ni ejecutada onchain**.

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
- El dry-run del despliegue mostro 192.055 gas y `0,038987165` test MON al
  max-fee estimado de 203 gwei. Los otros pasos aun no tienen estimacion RPC
  sobre el probe desplegado; no se debe presentar ese numero como coste total.

## Orden operativo

1. Revisar `git status`, saldos, chain id y gas actual. Simular el despliegue
   SIN `--broadcast`:

   `forge script script/DeployFaultProbe.s.sol:DeployFaultProbe --rpc-url https://testnet-rpc.monad.xyz`

2. Solo con autorizacion informada, desplegar el probe y verificar recibo,
   direccion y bytecode. La direccion impresa en el dry-run NO es real.
3. Simular y ejecutar por separado commit del agente, sello del retador y
   reveal, verificando cada recibo antes del siguiente. Los salts se generan y
   guardan fuera de Git; **nunca se pegan en un chat ni se imprimen**.
4. Leer `status`, `credits(agent)`, `credits(challenger)` y `escrowed()` onchain.
   Si el resultado es el esperado, cada beneficiario retira su propio credito.

No usar el antiguo DissentCore de Testnet: su politica de `AdapterFault` era
distinta. No realizar esta prueba en Mainnet.
