# Partner fit — ¿tu agente necesita Dissent?

Esta ficha sirve para decidir si vale la pena construir un adaptador conjunto.
No es una promesa de integración. La respuesta puede ser **no encaja**.

## La pregunta en una línea

> Does another app act on your agent's numerical decision, and is there a large
> allowed search space where outsiders could find a deterministically checkable
> counterexample?

## Los cinco requisitos

Un caso solo encaja si responde **sí** a los cinco:

1. **Consumidor:** otra aplicación, contrato o agente utiliza la cifra.
2. **Búsqueda:** el espacio de contraejemplos es demasiado grande o especializado
   para que el agente lo agote de forma trivial.
3. **Determinismo:** un contraejemplo concreto puede comprobarse bajo la regla
   pública sin un LLM decidiendo el veredicto.
4. **Procedencia:** las entradas y la contraevidencia pueden autenticarse o ya
   viven en una fuente onchain comprometida.
5. **Valor:** una salida falsa controla más valor que el coste del desafío.

## Lo mínimo que debe entregar el equipo

No necesitamos su agente completo. Necesitamos un caso real y reproducible:

```text
Claim name:
Who consumes it:
Unit / scale:
One real input:
Output produced by the agent:
Threshold used by the consumer:
Allowed counterevidence:
Public rule or formula:
Source and authentication of every input:
Approximate number of outputs:
What value can a false output move:
Current way the consumer verifies it:
```

No incluir claves, secretos, datos personales ni lógica propietaria que el equipo
no quiera publicar. Un caso que dependa de una fórmula secreta no es apto para el
recomputer público de Dissent.

## Qué aporta Dissent

Si el caso pasa el filtro:

- una implementación de `IRecomputer` específica del dominio;
- tests del valor base, evidencia válida, evidencia rechazada y cruce del umbral;
- medición de los límites de gas `R`, `V` y `maxEvidenceLen`;
- un compromiso y desafío completo en Monad Testnet;
- recibos enlazables para que el otro equipo demuestre la integración.

El equipo del dominio sigue siendo responsable de justificar la semántica de la
regla y la procedencia de sus datos. Dissent garantiza la mecánica de compromiso,
desafío y liquidación; no convierte una fórmula débil en verdad.

## Clasificación rápida

| Caso | Encaje | Motivo |
| --- | --- | --- |
| Score calculado desde datos onchain comprometidos | Posible | Procedencia y regla pueden auditarse |
| Restricción de riesgo con muchos escenarios posibles | Fuerte | Buscar el caso adverso es difícil; comprobar uno es exacto |
| Tarifa o recompensa bajo una regla pública | Posible | Solo si el cálculo no es trivial y controla suficiente valor |
| Probabilidad generada por un LLM | No | No existe re-ejecución determinista |
| Risk score desde una API sin firma ni prueba | No todavía | El contrato no sabe si la entrada es auténtica |
| Tres o cuatro escenarios enumerables | No comercial | El agente puede probarlos todos; solo sirve como demo |
| Predicción sobre un hecho futuro | No | Requiere un oracle o resolución externa |

## Mensaje dirigido para un equipo

```text
Hi, I’m Julieta (Alnitak), building Dissent for Metropolis Track 04.

Dissent is a bug bounty for agent decisions: the agent puts MON behind a
numerical boundary, and challengers compete to find an allowed counterexample
that crosses it.

I’m looking for one real output, not your whole project. If your agent publishes
a score, price, return, probability or safety limit that another component uses,
send me one example plus the public formula and the source of its inputs. I’ll
first tell you honestly whether it fits. If it does, I’ll help build and test the
adapter on Monad Testnet while you keep control of your domain logic.

It only fits if searching the allowed challenge space is non-trivial, a submitted
counterexample is deterministically checkable, and the inputs have verifiable
provenance.

Thanks — happy to compare notes even if the answer is that Dissent is not the
right layer for your project.
```

Public integration guide: <https://dissent-henna.vercel.app/docs.html#integration>

Evaluación de candidatos concretos de Metropolis:
[`METROPOLIS_CANDIDATES.md`](METROPOLIS_CANDIDATES.md).

## Evidencia que sí cuenta como tracción

- un pull request del otro equipo que importa o implementa la interfaz;
- una transacción de su agente contra DissentCore;
- su repositorio o demo enlazando la integración;
- una confirmación pública y específica del caso que planean usar.

Un like, una reacción o una conversación genérica no demuestra adopción.
