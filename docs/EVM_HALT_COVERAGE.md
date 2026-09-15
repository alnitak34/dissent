# Cobertura de fallos externos de la EVM

Estado: inventario de seguridad para la rama
`security-no-payable-adapter-fault`. El `CALL` con valor fue validado en validate
y recompute por GitHub Actions con Foundry 1.8.1. No es una auditoría ni una
prueba formal de exhaustividad.

Ejecución verificable:
<https://github.com/alnitak34/dissent/actions/runs/34999684775>

## Alcance y criterio

`DissentCore` llama `validateEvidence` y `recompute` mediante `STATICCALL`. Desde
el núcleo, los fallos de ejecución del adaptador colapsan en la misma señal:
`success == false`; una respuesta exitosa pero con ABI no canónico también se
rechaza. La política de esta rama no paga un bounty por ninguna de esas señales:
liquida la campaña como `Faulted`, devuelve el depósito al challenger y devuelve
la recompensa al agente.

La lista de `HaltReason` de REVM en el commit citado por la mentoría se usa como
inventario inicial. REVM no es la especificación normativa de Monad y su lista
puede cambiar. Por eso este documento separa:

- fallos ejercitados de punta a punta;
- variantes que comparten el mismo límite observable;
- estados que `STATICCALL` impide alcanzar por una ruta de creación o pago;
- huecos que todavía merecen una prueba dirigida.

Fuentes:

- REVM, `HaltReason` en el commit fijado por el mentor:
  <https://github.com/bluealloy/revm/blob/eb3803beaabb6623a87750e5b772d947f312d8e5/crates/context/interface/src/result.rs#L1102-L1145>
- EIP-214, semántica de `STATICCALL`:
  <https://eips.ethereum.org/EIPS/eip-214>
- EIP-1153, `TLOAD` permitido y `TSTORE` excepcional en contexto estático:
  <https://eips.ethereum.org/EIPS/eip-1153>
- Monad, límite de 30M por transacción y cobro por gas limit:
  <https://docs.monad.xyz/developer-essentials/changelog>

## Matriz

| Familia REVM | Estado en Dissent | Evidencia o razón |
| --- | --- | --- |
| `OutOfGas` | Cubierta como clase, no cada subtipo | `RecBurn`, `ValBurn`, return bomb y las regresiones con el piso funcional terminan en `Faulted` sin bounty. No se aislaron `Memory`, `MemoryLimit`, `Precompile`, `InvalidOperand` ni `ReentrancySentry`. |
| `OpcodeNotFound` / `InvalidFEOpcode` | Parcial | `invalid()` está probado en validate y recompute. No se desplegó bytecode crudo con cada opcode indefinido. |
| `InvalidJump` | Pendiente dirigido | Requiere bytecode crudo o generado expresamente; no tiene prueba propia todavía. |
| `NotActivated` | Dependiente del fork | Solo existe respecto de una revisión concreta. Debe comprobarse con la configuración efectiva de Monad, no presentarse como propiedad universal de Foundry. |
| `StackUnderflow` / `StackOverflow` / `OutOfOffset` | Pendiente dirigido | Son caminos de bytecode malformado o límites internos; no están aislados. Para el núcleo deberían observarse como `success == false`, pero eso es una inferencia hasta ejecutar los casos. |
| `CreateCollision` / `NonceOverflow` / límites de tamaño o prefijo de `CREATE` | No alcanzables como su categoría propia bajo la llamada estática | EIP-214 propaga el modo estático y prohíbe `CREATE`/`CREATE2`; el intento debe fallar primero como cambio de estado durante llamada estática. `SSTORE`, `LOG` y `TSTORE` ya prueban esa familia, no cada opcode. |
| `StateChangeDuringStaticCall` | Cubierta | `SSTORE` y `LOG` están probados en validate y recompute; `TSTORE` está probado en la suite aislada Cancun. Todos terminan sin bounty. |
| `CallNotAllowedInsideStatic` | Cubierta | Un `CALL` con valor dentro del adaptador está ejercitado en validate y recompute. Termina en `Faulted`, devuelve ambos principales y no paga bounty. |
| `OutOfFunds` / `OverflowPayment` | No alcanzables desde el `STATICCALL` directo con valor cero; cubierto el intento anidado de pago | Dissent no transfiere valor al adaptador. El test de `CALL` con valor comprueba que el intento anidado se rechaza en contexto estático antes de producir un pago. |
| `PrecompileError` / `PrecompileErrorWithContext` | Pendiente dirigido, impacto acotado | Falta un adaptador que propague un fallo real de precompile. Si la llamada exterior devuelve `false`, la política ya no paga bounty; falta demostrarlo con ese origen concreto. |
| `CallTooDeep` | Medida, no demostrada formalmente | La suite aislada intentó 1024 marcos con 30M, alcanzó 399 y falló antes de entrar a `challengeReveal`; la campaña quedó `Open` y no hubo pagos. |

## Fallos externos que no son una variante de `HaltReason`

También están cubiertos de punta a punta:

- `REVERT` explícito;
- returndata corto o de tamaño incorrecto;
- bool ABI no canónico;
- return bomb;
- gas insuficiente aportado por el challenger, que revierte antes de clasificar
  un `AdapterFault`;
- calldata ABI sobrante, que no cambia la liquidación probada.

## Límite que el inventario no resuelve

Un adaptador puede devolver datos ABI perfectamente canónicos y, aun así,
depender de `tx.origin`, bloque, timestamp, `PREVRANDAO`, gas o `TLOAD`. En ese
caso no hay halt que clasificar. Las pruebas actuales demuestran algunos de esos
comportamientos, pero el núcleo no puede decidir si el número es semánticamente
correcto. Esa responsabilidad sigue en la frontera de confianza del adaptador.

## Próximas pruebas, en orden

1. `InvalidJump` con runtime mínimo controlado.
2. Un fallo de precompile propagado por el adaptador.
3. Solo si aporta evidencia adicional: bytecode crudo para stack underflow,
   stack overflow y out-of-offset.

Estas pruebas no deben cambiar la política: ninguna falla técnica paga bounty.
Su función es demostrar que más orígenes de `success == false` llegan al mismo
resultado económico.
