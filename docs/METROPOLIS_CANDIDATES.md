# Candidatos reales de Metropolis para integrar Dissent

Estado de la revisión: **15 de septiembre de 2026**.

Este documento no afirma adopción. Registra proyectos públicos encontrados en
los canales de Monad y contrasta cada uno contra los cinco requisitos de
[`PARTNER_FIT.md`](PARTNER_FIT.md). Las conclusiones marcadas como
**interpretación** necesitan confirmación del equipo correspondiente.

## Prioridad 1 — ARF Onchain

Fuente primaria: <https://github.com/arf-foundation/arf-onchain>

### Hechos verificados

- ARF se presenta como proyecto de **Monad Metropolis**, en el mismo track de
  Trust, Identity & AI Infrastructure.
- Un motor fuera de la cadena produce una atestación firmada con `intentHash`,
  `policyHash`, `modelHash`, puntuación de riesgo, decisión y vencimiento.
- `ExecutionGuard` valida identidad, firma, política, expiración, replay y
  límites antes de permitir una operación.
- Su documentación dice expresamente que el contrato **no reproduce el modelo
  de riesgo completo onchain**. Verifica quién evaluó, qué intent evaluó y qué
  resultado firmó.
- El README no contiene un mecanismo de `challenge` o `dispute`, y el equipo
  busca integraciones y colaboradores.

### El hueco concreto

Una firma demuestra procedencia e integridad, no que la puntuación sea correcta.
ARF puede probar:

> Este evaluador autorizado firmó `risk = 0.18` para este intent y esta política.

Dissent puede intentar añadir una garantía distinta:

> El evaluador financió una búsqueda pública de un estado permitido que
> contradiga una propiedad falsable de esa versión de su política.

No reemplaza a ARF. ARF controla la ejecución; Dissent permite impugnar la
corrección de una propiedad **solo cuando** existe una regla pública,
determinista y barata de volver a ejecutar.

### Filtro de encaje

| Requisito | Estado | Evidencia o pregunta pendiente |
| --- | --- | --- |
| Otro componente consume la cifra | **Sí** | `ExecutionGuard` consume la atestación para aprobar, escalar o denegar. |
| Búsqueda adversarial no trivial | **Por confirmar** | Hay que elegir una propiedad con un espacio grande de intents o estados. |
| Witness determinista | **Por confirmar** | El modelo completo es offchain; necesitamos un invariante público del motor de referencia, no su lógica propietaria. |
| Procedencia verificable | **Sí, para la atestación** | La puntuación, el intent, la política y el modelo están firmados y enlazados. Falta acordar la procedencia del witness. |
| Valor superior al challenge | **Plausible, no validado** | ARF gobierna acciones económicas, pero el equipo debe dar un caso y valor concretos. |

### Petición mínima al equipo

No pedir su motor propietario. Pedir un solo invariante público del evaluador de
referencia, por ejemplo:

```text
For every intent satisfying public conditions X, an APPROVE attestation must
also satisfy numerical boundary Y.
```

Y solicitar:

1. una atestación de ejemplo;
2. la regla pública del invariante;
3. el espacio de estados que puede recorrer un challenger;
4. la fuente verificable de cada dato;
5. la acción económica que consume la atestación.

Si no pueden publicar una propiedad determinista, ARF no encaja como adaptador
de Dissent aunque siga siendo un vecino estratégico.

## Prioridad 2 — ParaMEV

Fuentes primarias:

- <https://github.com/krimdev/paramev>
- <https://mev.parascan.dev/docs>

### Hechos verificados

- ParaMEV mantiene un observatorio de MEV sobre Monad y una API pública.
- `/api/risk?pool=…` produce un nivel de riesgo y estadísticas recientes para
  que agentes de ejecución ajusten su slippage antes de operar.
- El repositorio publica metodología y arquitectura, pero declara que el motor
  de detección productivo y sus umbrales exactos no son públicos porque los
  atacantes podrían adaptarse.

### Filtro de encaje

| Requisito | Estado | Evidencia o pregunta pendiente |
| --- | --- | --- |
| Otro componente consume la cifra | **Sí, como interfaz diseñada** | La API está hecha para agentes de ejecución. No hay todavía un consumidor externo verificado por Dissent. |
| Búsqueda adversarial no trivial | **Probable** | El espacio de bloques, pools y patrones MEV es amplio. |
| Witness determinista | **No demostrado** | La regla exacta del risk score no es pública. |
| Procedencia verificable | **Posible** | Los hechos base provienen del RPC público, pero haría falta congelar el bloque y una regla canónica. |
| Valor superior al challenge | **Por confirmar** | Depende del tamaño de las operaciones que usen el score. |

ParaMEV solo pasa a implementación si el equipo acepta exponer un **invariante
estrecho**, no todo su detector, que pueda verificarse contra un bloque y recibos
identificados.

## No priorizar ahora

### Quantum Portfolio

Fuente primaria: <https://github.com/EmpowerTours/quantum-portfolio>

Produce asignaciones, retorno esperado y riesgo mediante optimización híbrida,
forecasting y hardware cuántico. Es un dominio económicamente valioso, pero la
salida no parece reproducible de forma exacta y barata en EVM. Podría aportar
una restricción determinista sobre la asignación final, pero eso sería una parte
pequeña que el propio agente puede comprobar exhaustivamente.

### Red Sentinel

Fuente pública: <https://app.redsentinel.xyz/attack/keone_hon>

Ofrece bounties para romper agentes mediante jailbreak, prompt injection o
ingeniería social. Es un **vecino narrativo y competidor por atención**, no el
segundo adaptador: su veredicto depende del comportamiento de un modelo y no de
una afirmación numérica determinista.

## Lectura de producto

**Interpretación:** el mejor caso de valor encontrado hasta ahora no es «póker
para otros dominios», sino **impugnar propiedades públicas de una atestación de
riesgo que otro protocolo usa para autorizar capital**.

La frase que concentra la diferencia es:

> A signature proves who produced a risk score. Dissent tests whether one
> falsifiable property of that score survives an open search for counterexamples.

Esto no está validado como demanda hasta que ARF u otro equipo responda con una
propiedad concreta y acepte probar la integración.

## Próxima acción externa propuesta

Enviar un mensaje dirigido a `@petterjuan`, no otro anuncio general:

```text
Hi Juan, I’m Julieta (Alnitak), building Dissent in the same Metropolis track.

I read ARF’s public architecture. ARF can prove who signed a risk score, which
intent it belongs to, and whether that attestation may execute. Dissent explores
a complementary question: can outsiders find one valid state that breaks a
public, falsifiable property of that model version, with the witness replayed
and paid on Monad?

I’m not asking for your proprietary engine. Do you have one narrow invariant in
the public reference evaluator that could be expressed as a deterministic
numerical boundary over a large intent space? If yes, I can first check the fit
and, only if it is genuine, help build the Dissent recomputer and testnet flow.

If the answer is no because the score cannot be deterministically recomputed,
that is useful too. I’d rather establish the trust boundary honestly than force
an integration.
```

Enviar el mensaje constituye contacto externo y requiere aprobación de Julieta
en el momento de enviarlo.
