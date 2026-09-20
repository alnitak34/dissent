# Ejecución funcional — Policy Bounty en Monad Testnet

Fecha: `2026-09-16` UTC.

Este documento registra hechos observados en recibos y lecturas onchain. No
contiene salts, claves, frases semilla ni contraseñas.

## Identidad

| Campo | Valor |
|---|---|
| DissentCore | `0x460f9F624da9e23c705c610E1263bf3641bCce23` |
| Policy Bounty recomputer | `0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d` |
| Agente | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| Challenger | `0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02` |
| Commitment id real | `0xeabab853de85ea81b5cb837ac289b03995e33063d0ce8b457d531a390a2f4bd0` |

## Recorrido onchain

| Paso | Tx | Bloque | Gas cobrado | Precio efectivo | Coste MON |
|---|---|---:|---:|---:|---:|
| Commit de `3 MON` | `0x82fa86b28ddcbc86673fa48e1cd30132a6408f99924b78d0557c885b101dcaa6` | 62934464 | 405.041 | 203 gwei | 0,082223323 |
| Primer sello | `0x5fa99ebdeea86d137db7387c6b33e6fa17a896b5182eec9244e90a346c30fa19` | 62935135 | 170.661 | 203,000000001 gwei | 0,034644183000170661 |
| Liquidación del sello vencido | `0x763c3e691570aa40a62a679593e09d9f24b4ae5cfe883f86b92d587c58f0473d` | 62944009 | 157.691 | 203,000000001 gwei | 0,032011273000157691 |
| Segundo sello | `0xef46f42f23fe0bc9dc7e400b0aa8083e4fa249c2a241bc829258b99b169eaa78` | 62945710 | 119.108 | 203,000000001 gwei | 0,024178924000119108 |
| Reveal exitoso | `0xeb4e80fdd0aba0e29ef8cb6abc81ac5b6ba475d5bdbcba6bd757a9cbcebbfb5f` | 62947743 | 22.211.703 | 105 gwei | 2,332228815 |
| Retiro challenger `3,1 MON` | `0x59d57ad7a1d4dae42f0c0eff9d4d748466c6b61f5e848824858e4e113784bec1` | 62949761 | 107.795 | 203,125 gwei | 0,021895859375 |
| Retiro agente `0,1 MON` | `0x5d6e96ce0b801de23d57d680dfa57022039fd41330033c448a803ece89412212` | 62950146 | 107.795 | 203 gwei | 0,021882385 |

Gas total cobrado en el recorrido, incluido el primer sello que venció:
`2,549064762375447460 MON` de testnet.

El depósito del primer sello no desapareció: `sweepExpiredSeal` lo acreditó al
agente y después se retiró. El coste irrecuperable del intento fue su gas.

## Resultado probado

- El recomputer derivó `baseValue = 0` al comprometer la campaña.
- La evidencia histórica `JhJd / 5c 9s 2h 6h 4c` produjo `newValue = 1`.
- El umbral era `0` con comparador `AtMost`; `1` refutó la afirmación.
- Se emitió `ChallengeSucceeded` con payout de `3,1 MON`.
- El compromiso terminó en `Status.Challenged`.
- El segundo sello terminó con `settled = true`.
- Antes de retirar, el challenger tenía crédito de `3,1 MON`.
- Después de ambos retiros, los créditos del challenger y del agente son `0` y
  `escrowed()` es `0`.

## Hallazgo operativo de gas

El flujo `--browser` de Foundry entregó a Rabby una petición de reveal con
`22.211.703` gas, por debajo del límite de 30M. Foundry registró la respuesta
como `user cancel`; la interfaz de Rabby había mostrado un error de simulación.
La misma transacción, firmada con el keystore local `dissent-challenger`, fue
incluida con éxito y Monad cobró exactamente los `22.211.703` gas declarados.

El multiplicador que funcionó fue `--gas-estimate-multiplier 105`. El valor no
es una constante universal: se sostiene aquí porque el contrato exigía
`txRequired = 20.972.966`, el gas declarado dejó 1.238.737 de margen y siguió
bajo 30M.

## Alcance de esta evidencia

Esta ejecución demuestra el camino real `commit → challengeCommit →
challengeReveal → ChallengeSucceeded → withdrawCredit` para una política y un
contraejemplo concretos en Monad Testnet. No demuestra auditoría externa, uso
por terceros, seguridad absoluta ni demanda de mercado.
