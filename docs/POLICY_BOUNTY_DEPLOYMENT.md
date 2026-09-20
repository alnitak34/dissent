# Checklist de despliegue — Policy Bounty endurecido

Este documento prepara el despliegue conjunto de un `DissentCore` nuevo y
`AlnitakPolicyBountyRecomputer` en Monad Testnet. No reutiliza el núcleo
desplegado el 2026-09-14: ese contrato conserva la política anterior de
`AdapterFault`.

**Estado actual:** ambos contratos fueron desplegados el 2026-09-16 y sus
invariantes onchain coinciden con el script. El recorrido funcional de
refutación válida y retiro de créditos se completó y está registrado en
[`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md). El 16-09-2026, ambos
contratos obtuvieron `Status: match` en Sourcify y MonadVision muestra
**«Contract Source Code Verified»** tanto para
[`DissentCore`](https://testnet.monadvision.com/address/0x460f9F624da9e23c705c610E1263bf3641bCce23)
como para
[`AlnitakPolicyBountyRecomputer`](https://testnet.monadvision.com/address/0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d).
Hay una prueba onchain concreta de `AdapterFault` por revert en `recompute`,
registrada en [`FAULT_PROBE.md`](FAULT_PROBE.md). La evidencia rechazada
todavía no se ha probado onchain. No presentar el caso de fallo como cobertura
exhaustiva ni confundir la verificación de fuente con una auditoría de seguridad.

## Estado validado antes del despliegue

| Campo | Valor verificado |
|---|---|
| Rama | `security-no-payable-adapter-fault` |
| Baseline del código desplegable | `079044a10ce38a7bd8225a70e91796ba7c6fbf37` |
| CI | `Validate AdapterFault security change` — success |
| CI run | <https://github.com/alnitak34/dissent/actions/runs/35050796748> |
| Script | `script/DeployPolicyBounty.s.sol` |
| Red | Monad Testnet |
| Chain ID | `10143` |
| RPC público | `https://testnet-rpc.monad.xyz` |

El dry-run del 2026-09-16 terminó con `Script ran successfully`. Foundry estimó
`5.385.001` unidades de gas y `1,093155203005385001 MON` al max fee estimado de
`203.000000001 gwei`. Es una instantánea de simulación, no una garantía del
coste del broadcast. Las direcciones del dry-run no son direcciones reales.

Monad Testnet tiene un límite de 30 millones de gas por transacción y cobra el
gas limit declarado, no solo el gas consumido. Por eso se debe repetir el
dry-run inmediatamente antes de firmar y no reemplazar manualmente los límites
calculados por Foundry.

## 1. Preflight sin wallet

- [ ] Confirmar la rama, que el `HEAD` local coincide con el remoto y que los
  archivos desplegables no cambiaron desde el baseline validado:

```powershell
$baseline = "079044a10ce38a7bd8225a70e91796ba7c6fbf37"
git status --short --branch
$localHead = git rev-parse HEAD
$remoteLine = git ls-remote --heads origin refs/heads/security-no-payable-adapter-fault
$remoteHead = ($remoteLine -split "\s+")[0]
if ($localHead -ne $remoteHead) { throw "HEAD local y remoto no coinciden" }
git merge-base --is-ancestor $baseline HEAD
if ($LASTEXITCODE -ne 0) { throw "el baseline no es ancestro de HEAD" }
git diff --exit-code $baseline HEAD -- foundry.toml src script/DeployPolicyBounty.s.sol
if ($LASTEXITCODE -ne 0) { throw "cambiaron archivos desplegables desde el baseline" }
```

- [ ] El working tree debe estar limpio y `$localHead` debe coincidir con
  `$remoteHead`.
- [ ] El baseline debe ser ancestro de `HEAD` y el `git diff` limitado a los
  archivos desplegables debe estar vacío.
- [ ] Confirmar que el CI del `HEAD` actual sigue en `success`.
- [ ] Ejecutar la validación local disponible:

```powershell
forge fmt --check script/DeployPolicyBounty.s.sol
forge build script/DeployPolicyBounty.s.sol --offline --no-lint
```

- [ ] Confirmar la red leyendo el RPC:

```powershell
$rpc = "https://testnet-rpc.monad.xyz"
cast chain-id --rpc-url $rpc
```

El resultado obligatorio es `10143`. Si difiere, detenerse.

## 2. Dry-run final, todavía sin transmitir

```powershell
forge script script/DeployPolicyBounty.s.sol:DeployPolicyBounty --rpc-url $rpc
```

- [ ] Debe terminar con `Script ran successfully` y `SIMULATION COMPLETE`.
- [ ] Registrar el gas total, max fee y `Estimated amount required` nuevos.
- [ ] Comprobar que la wallet de despliegue tiene al menos el importe estimado
  por Foundry. Si no lo tiene, detenerse.
- [ ] No añadir `--broadcast` hasta revisar estos tres datos.

## 3. Broadcast — requiere decisión y firma humana

El comando se prepara únicamente después de aprobar el dry-run final:

```powershell
$deployer = "<DIRECCION_DEPLOYER>"
forge script script/DeployPolicyBounty.s.sol:DeployPolicyBounty --rpc-url $rpc --sender $deployer --browser --broadcast
```

Antes de firmar cada transacción en Rabby:

- [ ] Red: Monad Testnet, chain ID `10143`.
- [ ] From: coincide exactamente con `$deployer`.
- [ ] La operación es creación de contrato; no envía valor a un tercero.
- [ ] El gas limit no supera 30 millones por transacción.
- [ ] El coste máximo mostrado es aceptable para la wallet de testnet.

No pegar una frase semilla ni una clave privada en terminal, chat, repo o
variable de entorno. El flujo previsto usa Rabby mediante `--browser`.

## 4. Registro del broadcast

Completar solo con datos de los recibos reales, nunca con las direcciones del
dry-run:

| Campo | Valor real |
|---|---|
| Fecha y hora UTC | `2026-09-16 04:07:10` / `04:07:40` |
| Commit `HEAD` desplegado | `75f7e1e15e51fa0895e4a3eb0c3b0c1992d47cbb` |
| Baseline del código desplegable | `079044a10ce38a7bd8225a70e91796ba7c6fbf37` |
| Deployer | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| DissentCore endurecido — dirección | `0x460f9F624da9e23c705c610E1263bf3641bCce23` |
| DissentCore endurecido — tx hash | `0x133aff75f159adfeb197e95795ec0fd0a212da4726b2be68c24edf7d06ae758b` |
| DissentCore endurecido — bloque | `62930184` |
| DissentCore endurecido — gas cobrado | `3.169.266` |
| DissentCore endurecido — coste | `0,643360998003169266 MON` |
| Policy Bounty recomputer — dirección | `0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d` |
| Policy Bounty recomputer — tx hash | `0xb90c7e0f30be7f9b1de50b473b356ce74c7d1ea3e42a2ea51008c23f872bccd1` |
| Policy Bounty recomputer — bloque | `62930284` |
| Policy Bounty recomputer — gas cobrado | `3.044.198` |
| Policy Bounty recomputer — coste | `0,617972194003044198 MON` |
| Gas cobrado total | `6.213.464` |
| Coste total en MON de testnet | `1,261333192006213464 MON` |

El coste real superó en `0,167841426443713464 MON` el último dry-run
(`1,0934917655625 MON`). La diferencia está registrada como observación; este
documento no atribuye una causa sin una medición específica.

## 5. Verificación onchain posterior

Definir las direcciones a partir de los recibos:

```powershell
$core = "<DISSENT_CORE_NUEVO>"
$rc = "<POLICY_BOUNTY_RECOMPUTER>"
```

### Bytecode presente

```powershell
$coreCode = cast code $core --rpc-url $rpc
if ($coreCode -eq "0x") { throw "DissentCore nuevo sin bytecode" }
$rcCode = cast code $rc --rpc-url $rpc
if ($rcCode -eq "0x") { throw "Policy Bounty recomputer sin bytecode" }
```

### Invariantes del núcleo

```powershell
cast call $core "MIN_WINDOW()(uint64)" --rpc-url $rpc
cast call $core "MONAD_TX_GAS_LIMIT()(uint256)" --rpc-url $rpc
cast call $core "REFERENCE_GAS_PRICE()(uint256)" --rpc-url $rpc
cast call $core "CHALLENGE_COMMIT_GAS()(uint256)" --rpc-url $rpc
cast call $core "MAX_EVIDENCE_LEN()(uint256)" --rpc-url $rpc
cast call $core "escrowed()(uint256)" --rpc-url $rpc
```

Resultados esperados, en orden: `3600`, `30000000`, `100000000000`, `200000`,
`131072`, `0`.

### Invariantes del recomputer

```powershell
cast call $rc "scale()(uint256)" --rpc-url $rpc
cast call $rc "domain()(bytes32)" --rpc-url $rpc
cast call $rc "POLICY_SPEC_HASH()(bytes32)" --rpc-url $rpc
cast call $rc "ORIGIN_COMMIT()(bytes20)" --rpc-url $rpc
cast call $rc "MARGIN_BP()(uint256)" --rpc-url $rpc
cast call $rc "canonicalInputs()(bytes)" --rpc-url $rpc
```

Valores esperados:

- `scale`: `1`.
- `domain`: `alnitak.river.safety.v1` codificado como `bytes32`.
- `POLICY_SPEC_HASH`:
  `0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0`.
- `ORIGIN_COMMIT`: `0xe6a7e49857602ac84257dc78f0960506f87cd7f3`.
- `MARGIN_BP`: `1500`.
- `canonicalInputs`: 96 bytes.

Si cualquier lectura difiere, no iniciar una campaña.

### Resultado onchain del 2026-09-16

| Comprobación | Resultado |
|---|---|
| Bytecode DissentCore | presente, `9.447` bytes |
| Bytecode Policy Bounty recomputer | presente, `9.064` bytes |
| Constantes del núcleo | todas coinciden |
| `escrowed` inicial | `0` |
| `scale` | `1` |
| `domain` | coincide |
| `POLICY_SPEC_HASH` | coincide |
| `ORIGIN_COMMIT` | coincide |
| `MARGIN_BP` | `1500` |
| `canonicalInputs` | `96` bytes |
| Saldo del deployer después del broadcast | `8,755817773961346481 MON` de testnet |

## 6. Verificación pública del código

Comandos ejecutados con las direcciones reales (no repetir para cambiar el
estado de los contratos):

```powershell
forge verify-contract $core src/DissentCore.sol:DissentCore --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

```powershell
forge verify-contract $rc src/adapters/AlnitakPolicyBountyRecomputer.sol:AlnitakPolicyBountyRecomputer --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

- [x] Ambos terminaron en `Status: match` el 16-09-2026.
- [x] Jobs de verificación:
  - DissentCore: [`32eb5e23-b4e9-4446-ba35-e53d80d45a9d`](https://sourcify-api-monad.blockvision.org/verify-ui/jobs/32eb5e23-b4e9-4446-ba35-e53d80d45a9d)
  - AlnitakPolicyBountyRecomputer: [`1446284a-e6eb-43b5-ae3c-2c37a396ce2d`](https://sourcify-api-monad.blockvision.org/verify-ui/jobs/1446284a-e6eb-43b5-ae3c-2c37a396ce2d)
- [x] MonadVision muestra «Contract Source Code Verified» en las dos direcciones.
  Antes del envío, `forge inspect ... deployedBytecode` coincidió byte por byte
  con `cast code` sobre chain ID 10143: 9.447 bytes para DissentCore y 9.064
  para el recomputer. El explorador muestra al deployer
  `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` y las transacciones de
  creación registradas en la tabla anterior.

## 7. Prueba funcional antes de anunciarlo

El despliegue no autoriza todavía una campaña pública.

- [x] Ejecutar un recorrido controlado con fondos de testnet sobre el núcleo
  nuevo: commit, challenge commit, espera, reveal y retiro de créditos; ver
  [`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md).
- [x] Probar una refutación válida en ese recorrido.
- [ ] Probar evidencia rechazada.
- [x] Probar un `AdapterFault` concreto (revert en `recompute`) y confirmar en
  eventos y créditos que el retador recupera solo su depósito y el agente su
  recompensa: nadie cobra un bounty por ese fallo técnico. Ver
  [`FAULT_PROBE.md`](FAULT_PROBE.md).
- [x] Confirmar que la web apunta a las direcciones nuevas y las identifica como
  Monad Testnet (`web/app.js`). La rama se fusionó a `master` el 20-09-2026 y la
  página pública en Vercel muestra este recorrido.
- [ ] Solo después, publicar la campaña o pedir una integración externa.

## 8. Parada y recuperación

Los contratos son inmutables: no existe rollback onchain.

- **Antes de firmar:** cancelar y corregir el script o la configuración.
- **Si solo una creación confirma:** registrar la dirección y tx como despliegue
  parcial; no anunciarla ni conectarla a la web. Revisar el recibo antes de
  decidir un despliegue de reemplazo.
- **Si una verificación post-deploy falla:** no crear compromisos ni depositar
  fondos; conservar los recibos como evidencia y preparar una versión nueva.
- **Si ya existe una campaña con fondos:** no asumir que desplegar otra versión
  mueve o recupera esos fondos. Analizar primero el estado y las rutas públicas
  de retiro del contrato existente.
- **Para retirar una versión de uso:** quitarla de la configuración de la web,
  marcarla explícitamente como obsoleta y desplegar una dirección nueva. La
  dirección anterior seguirá existiendo en la cadena.

## Fuentes operativas

- Monad changelog y parámetros de red:
  <https://docs.monad.xyz/developer-essentials/changelog>
- Verificación de contratos con Foundry:
  <https://docs.monad.xyz/guides/verify-smart-contract>
- API JSON-RPC de Monad:
  <https://docs.monad.xyz/reference/json-rpc/api>
