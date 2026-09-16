# Prueba funcional — Policy Bounty en Monad Testnet

Estado: **ejecutada con éxito en Monad Testnet el 2026-09-16**. El registro
completo, incluidos hashes, bloques, gas y el intento de sello vencido, está en
`docs/POLICY_BOUNTY_LIVE_RUN.md`.

## Contratos y roles

| Rol | Dirección |
|---|---|
| DissentCore endurecido | `0x460f9F624da9e23c705c610E1263bf3641bCce23` |
| Policy Bounty recomputer | `0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d` |
| Agente Dissent | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| Challenger | `0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02` |

El flujo usa el contraejemplo histórico `JhJd / 5c 9s 2h 6h 4c`. La evidencia
incluye cartas, bote, call y traza agresiva; no incluye el veredicto. El
recomputer debe derivar onchain `violation = 1`.

## Coste y peor caso antes de empezar

- El agente bloquea `3 MON` de testnet como recompensa y paga el gas de
  `commit`.
- El challenger bloquea `0,1 MON` y paga el gas de `challengeCommit` y del
  `challengeReveal` pesado.
- El reveal está presupuestado con `R=20.000.000`, `V=100.000` y evidencia de
  160 bytes. Su coste real debe medirse con dry-run justo antes de firmar.
- Si el challenger revela tarde o con salt/inputs incorrectos, la transacción
  revierte y el sello puede quedar expuesto a `sweepExpiredSeal`.

### Foto previa verificada

La simulación de la fase 1, ejecutada contra los contratos desplegados y sin
`--broadcast`, produjo:

| Dato | Valor |
|---|---:|
| `txRequired` del reveal | `20.972.966` gas |
| Recompensa mínima onchain al precio de referencia | `2,1172966 MON` |
| Recompensa elegida para la campaña | `3 MON` |
| Gas estimado para el commit | `351.035` gas |
| Coste estimado del gas del commit a 203 gwei | `0,071260105000351035 MON` |
| Necesidad inmediata estimada de la wallet agente | `3,071260105000351035 MON` |

La última cifra suma el `msg.value` de `3 MON` y la estimación de gas. Es una
estimación puntual del dry-run, no un precio garantizado. En esa lectura, la
wallet agente tenía `8,755817773961346481 MON` de testnet y la challenger
`20,017792243270892707 MON`; los balances deben releerse antes de transmitir.

## Variables locales

Los salts no se guardan en Git. En una terminal PowerShell dedicada:

```powershell
$rpc = "https://testnet-rpc.monad.xyz"
$agent = "0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A"
$challenger = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02"
```

Antes de cada fase se crearán los salts y variables necesarios. No pegar una
frase semilla ni una clave privada en la terminal.

Para crear un salt criptográficamente aleatorio sin imprimirlo:

```powershell
$env:DISSENT_AGENT_SALT = "0x" + [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
if ($env:DISSENT_AGENT_SALT.Length -ne 66) { throw "salt invalido" }
```

Para el challenger se usa el mismo procedimiento cambiando el nombre a
`DISSENT_CHALLENGER_SALT`. Ese segundo salt debe permanecer secreto y
disponible hasta completar el reveal.

## Fase 1 — publicar la campaña

Requiere `DISSENT_AGENT_SALT` no nulo y único. Simulación:

```powershell
forge script script/PolicyBountyFlow.s.sol:PolicyBountyCommit --rpc-url $rpc --sender $agent
```

Después del broadcast autorizado se registra el `Committed.id` del recibo como
`DISSENT_COMMITMENT_ID`. La simulación no es autoridad para ese id.

## Fase 2 — sellar el contraejemplo

Requiere el commitment id real y un `DISSENT_CHALLENGER_SALT` secreto, que debe
conservarse sin cambios hasta el reveal. Simulación:

```powershell
forge script script/PolicyBountyFlow.s.sol:PolicyBountyChallengeCommit --rpc-url $rpc --sender $challenger
```

Tras el broadcast hay que registrar el bloque de `ChallengeSealed`. El reveal
solo es válido desde cinco bloques después y durante los siguientes 7.200
bloques, ambos extremos incluidos.

## Fase 3 — revelar

Usa exactamente el mismo `DISSENT_COMMITMENT_ID` y
`DISSENT_CHALLENGER_SALT`. Simulación obligatoria:

```powershell
forge script script/PolicyBountyFlow.s.sol:PolicyBountyChallengeReveal --rpc-url $rpc --sender $challenger
```

Solo se transmite si la simulación confirma que el sello coincide, la ventana
está abierta, la evidencia es válida y el recomputer devuelve `1`.

Resultado onchain esperado: `Status.Challenged`, evento
`ChallengeSucceeded` y crédito del challenger de `3,1 MON`.

## Fase 4 — retirar el crédito

Primero se comprueba en lectura que el crédito sea exactamente `3,1 MON`.
Simulación:

```powershell
forge script script/PolicyBountyFlow.s.sol:PolicyBountyWithdraw --rpc-url $rpc --sender $challenger
```

El broadcast autorizado transfiere el crédito a la misma wallet challenger.

## Verificación final

- [x] `Commitment.status == Challenged`.
- [x] `Seal.settled == true`.
- [x] `ChallengeSucceeded.newValue == 1` y `threshold == 0`.
- [x] Payout acreditado antes del retiro: `3,1 MON`.
- [x] Crédito después del retiro: `0`.
- [x] Balance de `escrowed` vuelve a `0`.
- [x] Tx hashes, bloques, gas cobrado y coste registrados.

Esta prueba cubre el camino real de refutación. Los caminos
`ChallengeRejected` y `AdapterFault` permanecen cubiertos por CI; probarlos
onchain requiere campañas adicionales y no forma parte de este primer recorrido.
