# Decisión de seguridad: un fallo del adaptador no paga bounty

Estado del código: **implementado y fusionado a `master` el 20-09-2026 mediante
el PR #1 (merge commit `5cd68f4`). La suite normal, la suite aislada EIP-1153 y
la suite de profundidad pasaron en la validación de `master` #26; la validación
posterior #27 también terminó correctamente.**

Estado en Monad Testnet: **el núcleo endurecido se desplegó el 16-09-2026** en
[`0x460f9F624da9e23c705c610E1263bf3641bCce23`](https://testnet.monadvision.com/address/0x460f9F624da9e23c705c610E1263bf3641bCce23).
Se ejecutó una refutación válida con Policy Bounty y se retiraron ambos créditos;
ver [`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md). En una campaña
separada, un adaptador de prueba revirtió durante `recompute` y el núcleo
terminó en `Status.Faulted` sin bounty; recibo, costes y créditos en
[`FAULT_PROBE.md`](FAULT_PROBE.md). Son **dos recorridos concretos**, no una
validación exhaustiva. El 16-09-2026, la fuente del núcleo nuevo
obtuvo `Status: match` en Sourcify; la pestaña Contract de
[MonadVision](https://testnet.monadvision.com/address/0x460f9F624da9e23c705c610E1263bf3641bCce23)
muestra «Contract Source Code Verified». Esto no sustituye una auditoría
externa, que sigue pendiente.

Ejecución verificable más reciente:
<https://github.com/alnitak34/dissent/actions/runs/35049792323>

## Hallazgo

La versión anterior (núcleo
[`0x6dCD184c9c0db42FCD0De731F9a2855b38916758`](https://testnet.monadvision.com/address/0x6dCD184c9c0db42FCD0De731F9a2855b38916758))
trataba cualquier fallo observado en el `STATICCALL` al
adaptador como un `AdapterFault` pagable. El núcleo no puede distinguir de forma
general entre:

- un adaptador defectuoso o malicioso;
- un contexto de ejecución manipulado por quien envía el reveal;
- un `revert`, OOG, returndata malformado u otra forma de halt de la EVM;
- un comportamiento nuevo introducido por una futura versión de la EVM.

Como el challenger controla la transacción que ejecuta `challengeReveal`, pagar
directamente por un fallo externo convierte una clasificación ambigua en una
salida de fondos. La lista de `HaltReason` de REVM sirve como inventario inicial,
no como prueba de exhaustividad:

<https://github.com/bluealloy/revm/blob/eb3803beaabb6623a87750e5b772d947f312d8e5/crates/context/interface/src/result.rs#L1102-L1145>

La revisión fue motivada por feedback externo recibido en la mentoría de
Metropolis el 15 de septiembre de 2026. Ese feedback no sustituye una auditoría.

## Regla nueva

Solo un resultado canónico del recomputer que cruce el umbral puede pagar el
bounty.

Si `validateEvidence` o `recompute` fallan técnicamente con el gas prometido:

1. el compromiso pasa a `Faulted`;
2. el sello queda liquidado;
3. el challenger recupera únicamente su depósito;
4. el agente recupera únicamente su recompensa;
5. `AdapterFaulted` registra fase y ambos reembolsos;
6. nadie cobra un bounty.

Esto elimina el pago falso basado únicamente en un fallo de ejecución. No
demuestra quién causó el fallo.

## Riesgo restante, explícito

Un agente malicioso puede registrar un adaptador que funcione al crear el
compromiso y falle al recibir evidencia. Así puede terminar la campaña como
`Faulted` y recuperar su recompensa en vez de perderla frente a un
contraejemplo válido. El challenger recupera el depósito, pero paga el gas.

Por tanto, `Faulted` significa **campaña inválida**, no "agente inocente" ni
"challenger equivocado". La mitigación actual es reputacional y observable:
adaptador inmutable, fuente verificada, versión reconocible y eventos
indexables. El MVP no incluye gobernanza ni resolución externa.

## Cobertura validada

`test/AdapterFault.t.sol` cubre fallos de validate y recompute por revert, OOG,
return bomb, returndata corto, tamaño incorrecto, bool no canónico, `INVALID` y
violaciones de `STATICCALL` mediante `SSTORE`, `LOG` y `CALL` con valor. También
cubre un `InvalidJump` originado en runtime crudo y un fallo propagado desde la
precompile `0x08` con longitud inválida. Sus aserciones demuestran:

- `credits(challenger) == deposit`;
- `credits(agent) == reward`;
- `escrowed == 0`;
- estado `Faulted`;
- el sello no puede barrerse después.

Dos regresiones adicionales hacen que `validate` o `recompute` consuman casi
todo su cap y verifican que la rama de fault todavía liquida los dos créditos
con `functionGasFloor + ENTRY_OVERHEAD`. Esto valida de punta a punta la
suficiencia funcional del presupuesto modelado para esos dos caminos. No es una
medición aislada del gas exacto de `_settleFault`.

`test/EvidenceFalseRegresion.t.sol` cubre rechazos canónicos dependientes de
`tx.origin`, `block.number`, `gasleft()`, `block.timestamp` y `PREVRANDAO`, y una
llamada exterior con calldata ABI sobrante. En esos casos el retador recupera
su depósito y el agente no cobra. Esto **no** demuestra que un recomputer
dependiente del contexto sea determinista: un retorno canónico distinto sigue
perteneciendo a la frontera de confianza del adaptador.

`security-tests/TransientStorageBoundary.t.sol` se ejecuta aparte con target
Cancun. Verifica las dos caras de EIP-1153:

- un `TSTORE` ejecutado durante el `STATICCALL` termina en `Faulted`, devuelve
  depósito y recompensa a sus dueños y no paga bounty;
- un `TLOAD` sí puede leer estado transitorio preparado por el challenger en una
  llamada anterior de la misma transacción y producir un `int256` canónico que
  cruza el umbral;
- sin el `TSTORE` previo, el mismo adaptador y la misma evidencia no refutan.

La segunda prueba demuestra una **limitación**, no una defensa: el núcleo no
puede distinguir ese número contextual de una refutación semánticamente válida.
La prueba corre en el REVM de Foundry con reglas Cancun; todavía no es una
transacción de validación ejecutada en Monad Testnet.

Fuentes normativas: [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) permite
`TLOAD` en contexto estático y hace excepcional `TSTORE`; [EIP-214](https://eips.ethereum.org/EIPS/eip-214)
define las restricciones generales de `STATICCALL`.

`security-tests/CallDepthBoundary.t.sol` limita la llamada exterior a 30M de
gas e intenta interponer 1024 llamadas antes de `challengeReveal`. En Foundry:

- el control con profundidad 0 completó y pagó una refutación real;
- el intento profundo alcanzó 399 marcos y la siguiente llamada falló;
- `challengeReveal` no se ejecutó, el compromiso quedó `Open` y no hubo créditos
  ni bounty para ninguna parte.

Esto es evidencia reproducible de que el ataque no alcanzó la profundidad
máxima bajo el límite probado; no es una demostración formal para todos los
clientes ni una ejecución en Monad Testnet. Solidity documenta una profundidad
máxima de 1024 y señala que la regla 63/64 de EIP-150 dificulta llegar a ella:
<https://docs.soliditylang.org/en/latest/security-considerations.html#call-stack-depth>

## Trabajo pendiente antes de presentarlo como versión pública validada

1. Medir de forma aislada el gas exacto de `_settleFault` si se quiere publicar
   el headroom numérico de `SETTLE_RESERVE`; las regresiones actuales solo
   validan que la envolvente funcional alcanza.
2. Validar EIP-1153 y profundidad también contra Monad Testnet si se decide
   presentarlos como evidencia específica de red; hoy son pruebas de Foundry
   (EIP-1153 usa target Cancun).
3. Decidir si los casos de bytecode malformado todavía no aislados (stack
   underflow, stack overflow y out-of-offset) aportan evidencia material. El
   inventario `docs/EVM_HALT_COVERAGE.md` ya separa lo cubierto, lo parcial y lo
   no alcanzable bajo `STATICCALL`; no afirma exhaustividad formal.
4. Someter el cambio a revisión externa; la suite no sustituye una auditoría.
5. **Cerrado el 20-09-2026:** fusionado a `master` mediante una decisión
   explícita de aceptar los riesgos restantes; la auditoría externa sigue
   pendiente y no debe darse por sustituida por el merge.
6. **Despliegue y dos caminos concretos realizados:** el núcleo nuevo y el
   recomputer de Policy Bounty están en Testnet; la web pública usa sus
   direcciones y recibos del camino exitoso. La fuente ya se verificó
   públicamente. Un `AdapterFault` por revert en `recompute` también quedó
   probado onchain, pero no aparece aún en el replay principal; decidir si
   aporta valor visible antes de añadirlo. El núcleo anterior sigue existiendo
   en otra dirección y conserva su política previa.
