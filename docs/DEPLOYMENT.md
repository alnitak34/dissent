# Despliegue — Monad testnet

> **Despliegue histórico (2026-09-14).** Las direcciones de este documento
> corresponden al núcleo anterior al cambio de política de `AdapterFault` y no
> deben reutilizarse para Policy Bounty. El procedimiento del candidato
> endurecido está en
> [`POLICY_BOUNTY_DEPLOYMENT.md`](./POLICY_BOUNTY_DEPLOYMENT.md).

El `script/Deploy.s.sol` actual ya prepara la arquitectura nueva con registro y
**no reproduce** este despliegue histórico. Las direcciones, transacciones y
comandos que siguen documentan lo ejecutado el 14-09-2026; no son instrucciones
para desplegar el código actual.

Tras crear los contratos, el script corre `require`s
(`MIN_WINDOW == 1 hours`, `escrowed == 0`, `scale == 1e18`,
`domain == "alnitak.river.mix.v1"`). Qué autoridad tienen:

- **Durante el dry-run** (sin `--broadcast`) esos `require` verifican los contratos
  creados **en la simulación**, no una dirección real de la cadena.
- **Después del broadcast**, la autoridad son los **recibos de transacción** y las
  comprobaciones **`cast code` / `cast call` contra las direcciones realmente
  desplegadas** (abajo). El `require` del script no reemplaza esa verificación.

| Parámetro | Valor |
|---|---|
| Red | Monad testnet |
| Chain ID | 10143 |
| RPC público | `https://testnet-rpc.monad.xyz` |

La clave del deployer **no está en el repo**. El despliegue real se firmó con
Rabby mediante `--browser`; Foundry nunca recibió la frase semilla ni la clave
privada. El script no contiene claves, mnemonics ni RPC con credenciales.

## Simulación (sin transmitir)

```powershell
forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz
```

Sin `--broadcast` y sin cuenta real: no manda ninguna transacción.

## Broadcast ejecutado

El 2026-09-14 se transmitió desde
`0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` con Rabby:

```powershell
forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz --sender 0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A --browser --broadcast
```

El coste real conjunto fue `1.084975318005344706 MON` de testnet: 5,344,706
unidades de gas cobradas a `203.000000001 gwei`.

## Verificaciones posteriores al broadcast (PowerShell)

```powershell
$core = "0x6dCD184c9c0db42FCD0De731F9a2855b38916758"
$rc = "0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38"
$rpc = "https://testnet-rpc.monad.xyz"

cast call $core "MIN_WINDOW()(uint64)" --rpc-url $rpc     # 3600
cast call $core "escrowed()(uint256)" --rpc-url $rpc      # 0
cast call $rc "scale()(uint256)" --rpc-url $rpc           # 1000000000000000000
cast call $rc "domain()(bytes32)" --rpc-url $rpc          # "alnitak.river.mix.v1"

# bytecode presente:
$code = cast code $core --rpc-url $rpc
if ($code -eq "0x") { throw "DissentCore sin bytecode" }
$code = cast code $rc --rpc-url $rpc
if ($code -eq "0x") { throw "AlnitakRiverRecomputer sin bytecode" }
```

## Verificación pública del código (solo DESPUÉS del broadcast, con direcciones reales)

Requiere Foundry ≥ 1.8 y, en `foundry.toml`, `cbor_metadata = true`,
`bytecode_hash = "none"`, `use_literal_content = true` (ya configurados).
Fuente oficial: <https://docs.monad.xyz/guides/verify-smart-contract/foundry>.

```powershell
forge verify-contract 0x6dCD184c9c0db42FCD0De731F9a2855b38916758 src/DissentCore.sol:DissentCore --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

```powershell
forge verify-contract 0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38 src/adapters/AlnitakRiverRecomputer.sol:AlnitakRiverRecomputer --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

Ambos trabajos terminaron con `Status: match`:

- DissentCore: job `e3e9deb9-d29e-4e23-8d67-51951c57875c`.
- AlnitakRiverRecomputer: job `956bedbe-8190-48a9-8203-668f731b52a8`.

## Registro del despliegue

| Campo | Valor |
|---|---|
| Fecha (UTC) | 2026-09-14 |
| Deployer | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| DissentCore — dirección | `0x6dCD184c9c0db42FCD0De731F9a2855b38916758` |
| DissentCore — tx hash | `0xcb60911a9a5669d5dbc3c237d325290ebbbc04e25dfa8c13250425b9bcc1a5d0` |
| DissentCore — bloque | 62368495 (2026-09-14 04:12:35 UTC) |
| AlnitakRiverRecomputer — dirección | `0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38` |
| AlnitakRiverRecomputer — tx hash | `0x216123a7342d166b5829fa8db1883260d63e086d52a8916bd2798e99206e4cf1` |
| AlnitakRiverRecomputer — bloque | 62369406 (2026-09-14 04:17:13 UTC) |

Las dos creaciones pueden quedar en **bloques distintos**; se registran por
separado, no se asume que compartan bloque.
