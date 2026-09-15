# Decisión de seguridad: un fallo del adaptador no paga bounty

Estado: **cambio implementado en el working tree; compilación y pruebas
pendientes porque Windows Application Control bloquea `forge.exe`; no
desplegado**.

## Hallazgo

La versión desplegada trataba cualquier fallo observado en el `STATICCALL` al
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

## Cobertura existente que debe volver a pasar

`test/AdapterFault.t.sol` cubre fallos de validate y recompute por revert, OOG,
return bomb, returndata corto, tamaño incorrecto y bool no canónico. Sus
aserciones ahora deben demostrar:

- `credits(challenger) == deposit`;
- `credits(agent) == reward`;
- `escrowed == 0`;
- estado `Faulted`;
- el sello no puede barrerse después.

## Trabajo pendiente antes de desplegar

1. Ejecutar la suite completa y el lint en un entorno donde Foundry esté
   permitido.
2. Volver a medir `SETTLE_RESERVE`: la rama de fault ahora hace dos créditos en
   vez de uno. No se debe asumir que la medición anterior cubre el cambio.
3. Añadir regresiones para calldata ABI con trailing bytes, `TIMESTAMP`,
   `PREVRANDAO`, transient storage y fallos por profundidad de llamada cuando el
   entorno de pruebas permita reproducirlos con fidelidad.
4. Enumerar sistemáticamente las formas de fallo externas y verificar que todas
   terminan en reembolso, nunca en bounty.
5. Desplegar un `DissentCore` nuevo y actualizar web, direcciones y recibos. El
   contrato existente en testnet conserva la política anterior.
