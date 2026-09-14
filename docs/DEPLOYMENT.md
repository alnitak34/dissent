# Despliegue — Monad testnet

Script: [`script/Deploy.s.sol`](../script/Deploy.s.sol). Despliega `DissentCore` y
`AlnitakRiverRecomputer` (ninguno tiene argumentos de constructor).

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

La clave del deployer **no está en el repo**: la aporta un keystore/cuenta de
Foundry por fuera (`--account`). El script no contiene claves, mnemonics,
direcciones personales ni RPC con credenciales.

## Simulación (sin transmitir)

```powershell
forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz
```

Sin `--broadcast` y sin cuenta real: no manda ninguna transacción.

## Broadcast (documentado; NO ejecutado todavía)

Crear el keystore fuera del repo (interactivo; la clave no se pega en línea) y
fondear la dirección con el faucet de Monad testnet **antes** de transmitir:

```powershell
cast wallet import monad-deployer --interactive
```

```powershell
forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet-rpc.monad.xyz --account monad-deployer --broadcast
```

## Verificaciones posteriores al broadcast (PowerShell)

```powershell
$core = "<DIR_DissentCore>"
$rc = "<DIR_AlnitakRiverRecomputer>"
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
forge verify-contract <DIR_DissentCore> src/DissentCore.sol:DissentCore --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

```powershell
forge verify-contract <DIR_AlnitakRiverRecomputer> src/adapters/AlnitakRiverRecomputer.sol:AlnitakRiverRecomputer --chain 10143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/
```

Estos comandos solo se ejecutan **después** del broadcast y con las **direcciones
reales** desplegadas.

## Registro del despliegue (completar después del broadcast)

| Campo | Valor |
|---|---|
| Fecha (UTC) | _(pendiente)_ |
| Deployer | _(pendiente)_ |
| DissentCore — dirección | _(pendiente)_ |
| DissentCore — tx hash | _(pendiente)_ |
| DissentCore — bloque | _(pendiente)_ |
| AlnitakRiverRecomputer — dirección | _(pendiente)_ |
| AlnitakRiverRecomputer — tx hash | _(pendiente)_ |
| AlnitakRiverRecomputer — bloque | _(pendiente)_ |

Las dos creaciones pueden quedar en **bloques distintos**; se registran por
separado, no se asume que compartan bloque.
