# Checklist de despliegue — Policy Bounty endurecido

Este documento prepara el despliegue conjunto de un `DissentCore` nuevo y
`AlnitakPolicyBountyRecomputer` en Monad Testnet. No reutiliza el núcleo
desplegado el 2026-09-14: ese contrato conserva la política anterior de
`AdapterFault`.

## Estado validado antes del despliegue

| Campo | Valor verificado |
|---|---|
| Rama | `security-no-payable-adapter-fault` |
| Commit local/remoto | `079044a10ce38a7bd8225a70e91796ba7c6fbf37` |
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

- [ ] Confirmar que se está en la rama y commit exactos:

```powershell
git status --short --branch
git rev-parse HEAD
git ls-remote --heads origin refs/heads/security-no-payable-adapter-fault
```

- [ ] El working tree debe estar limpio y los dos hashes deben ser
  `079044a10ce38a7bd8225a70e91796ba7c6fbf37`.
- [ ] Confirmar que el CI del hash exacto sigue en `success`.
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
| Fecha y hora UTC | PENDIENTE |
| Commit desplegado | `079044a10ce38a7bd8225a70e91796ba7c6fbf37` |
| Deployer | PENDIENTE |
| DissentCore endurecido — dirección | PENDIENTE |
| DissentCore endurecido — tx hash | PENDIENTE |
| DissentCore endurecido — bloque | PENDIENTE |
| Policy Bounty recomputer — dirección | PENDIENTE |
| Policy Bounty recomputer — tx hash | PENDIENTE |
| Policy Bounty recomputer — bloque | PENDIENTE |
| Gas cobrado total | PENDIENTE |
| Coste total en MON de testnet | PENDIENTE |

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

## 6. Verificación pública del código

Ejecutar solo con las direcciones reales:

```powershell
forge verify-contract $core src/DissentCore.sol:DissentCore --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

```powershell
forge verify-contract $rc src/adapters/AlnitakPolicyBountyRecomputer.sol:AlnitakPolicyBountyRecomputer --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

- [ ] Ambos deben terminar en `Status: match`.
- [ ] Registrar ambos job IDs o URLs de verificación.
- [ ] Abrir las direcciones en el explorador y comprobar bytecode, creador y
  transacciones de creación.

## 7. Prueba funcional antes de anunciarlo

El despliegue no autoriza todavía una campaña pública.

- [ ] Ejecutar un recorrido controlado con fondos de testnet sobre el núcleo
  nuevo: commit, challenge commit, espera, reveal y retiro de créditos.
- [ ] Probar una refutación válida.
- [ ] Probar evidencia rechazada.
- [ ] Probar un `AdapterFault` y confirmar en eventos y créditos que el retador
  recupera solo su depósito y el agente recupera su recompensa: nadie cobra un
  bounty por el fallo técnico.
- [ ] Confirmar que la web apunta a las direcciones nuevas y las identifica como
  Monad Testnet.
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
