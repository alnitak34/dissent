# Solicitud de revisión externa — Dissent

Estado: material para pedir una revisión técnica, **no** una auditoría ni una
afirmación de seguridad. El cambio se fusionó a `master` el 20-09-2026 mediante
el PR #1 (merge commit `5cd68f4`). No enviar fondos reales ni usar el adaptador
de prueba en producción.

## Qué revisar

Dissent permite que un agente financie una recompensa para una afirmación
numérica. El agente aporta al `commit` la dirección de un `IRecomputer`,
entradas, umbral y recompensa. El núcleo calcula el valor base, guarda la
dirección del adaptador, y después acepta evidencia sellada de un retador. El
adaptador calcula el valor nuevo y el núcleo liquida según el umbral.

Código principal: [`src/DissentCore.sol`](../src/DissentCore.sol) y
[`src/IRecomputer.sol`](../src/IRecomputer.sol). El caso funcional está en
[`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md); el caso de fallo
técnico en [`FAULT_PROBE.md`](FAULT_PROBE.md). Ambos son ejecuciones concretas
en Monad Testnet, no cobertura exhaustiva. La decisión de seguridad y las
pruebas adversariales están en
[`SECURITY_DECISION_ADAPTER_FAULT.md`](SECURITY_DECISION_ADAPTER_FAULT.md).

## Invariantes que pedimos cuestionar

1. Un bounty solo sale de un `recompute` que devuelve un `int256` canónico y
   cruza el umbral. Un `revert`, OOG o retorno ABI inválido nunca paga bounty.
2. Ante `AdapterFault`, el sello se liquida, el retador recupera solo su
   depósito y el agente solo su recompensa; no queda un segundo camino de
   `sweepExpiredSeal` sobre ese sello.
3. Gas insuficiente aportado por el retador revierte sin clasificar un
   adaptador honesto como `Faulted`. El modelo debe caber en el límite
   de 30 millones de gas por transacción de Monad.
4. Con varios sellos, `Challenged`, `Faulted`, `ChallengeRejected`, `void`,
   `sweep` y `reclaim` no crean créditos por encima de los depósitos recibidos
   ni dejan depósitos sin destino.

## Límites conocidos; no pedir que se asuman resueltos

- El **agente elige** la dirección del adaptador. El núcleo no certifica que
  su fórmula sea correcta, ni vincula el `codehash`, ni impide un proxy o un
  adaptador con estado mutable. El consumidor debe aprobar la regla antes de
  confiar en ella.
- Un agente puede elegir un adaptador que funcione al `commit` y falle al
  revelar. Con la política actual la campaña queda `Faulted`, el retador
  recupera su depósito pero pierde el gas, y el agente recupera su recompensa.
- Un adaptador puede devolver números canónicos dependientes de contexto EVM
  (`block.timestamp`, `PREVRANDAO`, `TLOAD`, etc.). `STATICCALL` no prueba que
  el resultado dependa solo de `inputs` y `evidence`.
- Las pruebas locales, la verificación de fuente y dos recorridos en Testnet
  no sustituyen una auditoría externa ni demuestran demanda de mercado.

## Preguntas prioritarias para quien revise

1. ¿Hay alguna secuencia de llamadas o estado del contrato que pague bounty
   sin un valor canónico que cruce el umbral, o que permita cobrar dos veces?
2. ¿Puede un retador manipular gas, calldata, profundidad o contexto para
   convertir un adaptador honesto en `AdapterFault` o un número canónico falso?
3. ¿El modelo de gas y las reservas EIP-150 bastan en Monad para todas las
   ramas de liquidación, también con evidencia de longitud máxima y varios
   sellos? Indicar el caso reproducible si no.
4. ¿Qué pruebas faltan para validar la conservación de fondos y el estado de
   cada sello bajo combinaciones adversariales de varios retadores?
5. ¿Qué política mínima de aceptación de adaptadores necesitaría una
   aplicación real para que el resultado sea útil, sin afirmar que el núcleo
   comprueba algo que hoy no comprueba?

No se pide certificar el sistema como seguro. Se pide un contraejemplo
reproducible o una lista priorizada de riesgos residuales, citando función,
precondiciones y efecto económico de cada hallazgo.
