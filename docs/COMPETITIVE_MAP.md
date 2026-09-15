# Mapa competitivo de Dissent

Estado de la revisión: **15 de septiembre de 2026**. Este documento registra
productos vecinos encontrados y la diferencia comprobable. Una búsqueda abierta
no demuestra inexistencia mundial; por tanto, Dissent no debe presentarse como
"el primero" ni como una categoría sin competidores.

## La frontera exacta

La propuesta que se contrasta es:

> Un agente identifica una versión de su política, publica un mandato
> determinista y financia una recompensa. Participantes externos buscan estados
> válidos que rompan ese mandato. Un contrato reproduce un único contraejemplo y
> liquida la recompensa sin juez humano ni LLM.

## Vecinos verificados

| Proyecto | Lo que ya hace | Diferencia verificable con Dissent |
| --- | --- | --- |
| [AgentProof](https://github.com/evanl666/agentproof) | Especificaciones de comportamiento, simulación adversarial, replay de tráfico y pruebas de alcanzabilidad que entregan una ruta de contraejemplo. También ofrece red teaming con adversario y juez LLM. | Es una suite de evaluación y guard de ejecución. Su README no describe una campaña pública financiada por el agente ni liquidación permissionless del primer contraejemplo. |
| [Praxen](https://github.com/open-agent-ai-security/praxen) | Compara un *Worker Remit* con código, estado o historial y produce hallazgos sobre divergencia entre intención y comportamiento. | Produce un informe para revisión experta y declara que funciona antes del despliegue. No es un mercado de búsqueda ni una liquidación onchain. |
| [AgentMandate](https://github.com/mrwersa/agentmandate) | Modela autoridad, encuentra rutas de incumplimiento, exporta escenarios y verifica trazas contra un manifiesto. | Declara explícitamente que no ejecuta los escenarios ni aplica enforcement. Dissent empieza donde existe un verificador determinista aceptado y añade incentivo y liquidación. |
| [Agent Bounties](https://github.com/NSPG13/agent-bounties) | Red financiada donde agentes publican trabajos. Su modo de primera entrega válida diseña commit/reveal, bonos y un verificador comprometido. | Es el vecino mecánico más próximo. El objeto publicado es un trabajo que necesita una solución; en Dissent es una política existente que necesita un contraejemplo que la invalide. |
| [AgentGuard / Agent Control Plane](https://github.com/0xCaptain888/agent-control-plane) | Aplica permisos, presupuestos y límites antes de ejecutar; verifica resultados y libera o congela fondos usando un verificador configurado. | Es control de ejecución y settlement. Dissent no bloquea una acción: abre búsqueda pública sobre lo que la política olvidó contemplar. |
| [AgentBond](https://agentbond.online/) | Agentes ponen collateral por trabajos; disputas pueden quemar o transferir ese stake. | Su alcance es reputación, trabajo y disputas con verificadores. Dissent se restringe a propiedades deterministas que el contrato puede volver a ejecutar. |
| [AXON ConfidenceBond](https://github.com/MUTHUKUMARAN-K-1/axon/blob/main/contracts/ConfidenceBond.sol) | AXON bloquea 0,001 OKB tras cada veredicto `SAFE`; cualquiera puede llamar `challenge(token)` y cobrar si el ledger muestra después `HIGH RISK` dentro de siete días. El contrato confirma que solo `oracle` publica veredictos y que `challenge(token)` no recibe evidencia. Está desplegado en X Layer mainnet. | Es el vecino económico más cercano encontrado: dinero detrás de un veredicto y pago a un challenger. Sin embargo, su condición de éxito es un **cambio posterior del propio oráculo**. Dissent fija una política y permite presentar ahora un estado concreto que el recomputer reproduce como contraejemplo; no depende de que el emisor cambie su veredicto. |
| [ARF Onchain](https://github.com/arf-foundation/arf-onchain) | Proyecto de Metropolis que registra atestaciones firmadas de riesgo y condiciona la ejecución a identidad, política, firma, límites y decisión. Declara que no reproduce el modelo de riesgo completo onchain. | ARF prueba procedencia y aplica autorización. Dissent intenta financiar y liquidar una búsqueda de contraejemplos contra una propiedad pública del modelo. Es posible socio y competidor de infraestructura; el encaje depende de que exista un invariante determinista publicable. |
| [Red Sentinel](https://app.redsentinel.xyz/attack/keone_hon) | Arena con bounties para romper agentes mediante jailbreak, prompt injection e ingeniería social. | Es el vecino narrativo más visible: «rompe al agente y cobra». Su objeto es el comportamiento conversacional de un modelo; Dissent restringe el veredicto a un contraejemplo numérico que un contrato reproduce sin LLM. |

## Lectura sostenida

### Lo que sí puede decirse

- Dissent combina tres elementos que en los materiales revisados aparecen por
  separado: una política versionada del agente, búsqueda externa financiada de
  contraejemplos y adjudicación determinista onchain.
- El objeto del bounty no es "hacer un trabajo" ni "juzgar una respuesta": es
  encontrar un estado permitido que rompa el límite de una política que pretende
  controlar valor.
- El caso Alnitak aporta una decisión histórica real y un control positivo; el
  veredicto no usa si la mano ganó o perdió.

### Lo que no puede decirse

- Que Dissent inventó los bug bounties, los contraejemplos, el commit/reveal o
  los verificadores deterministas.
- Que no existe otro producto igual en todo el mundo.
- Que ausencia de un challenge prueba que una política es segura.
- Que la mecánica constituye una barrera técnica difícil de copiar.

## Amenaza principal

La amenaza no es AgentProof: su producto central es testing. AXON demuestra que
el patrón «un agente pone dinero detrás de un veredicto y un challenger puede
cobrar» ya está construido y desplegado. Agent Bounties demuestra que también
existen mercados con commit/reveal y verificadores. La amenaza más directa es
que cualquiera de ellos añada un modo «encuentra un contraejemplo de esta
política». Por eso la defensa de Dissent no puede ser la frase. Debe ser:

1. especificación de política y evidencia canónicas;
2. adaptadores seguros que nunca conviertan bytes hostiles en un pago falso;
3. herramientas para buscar offchain y verificar un witness barato onchain;
4. integraciones donde una aplicación realmente condicione permisos o capital a
   una campaña Dissent.

## Consecuencia para la presentación

No abrir con "reputación para agentes" ni con "seguridad de IA". Ambas categorías
están saturadas. Abrir con una acción visible:

> **This agent put 3 MON on its own policy. One valid state broke it. Monad paid
> the proof.**

Después explicar la categoría: pruebas y guards buscan fallos con capacidad
interna; Dissent ofrece dinero para que cualquiera busque lo que el equipo no
pensó probar, y solo paga una evidencia que el recomputer registrado puede
reproducir.

Una segunda frase, orientada a infraestructura de riesgo, queda respaldada por
el hueco documentado en ARF:

> **A signature proves who produced a risk score. It does not prove the score
> is right. Dissent pays the counterexample.**

No usarla para afirmar que ARF está integrado. Hoy es una explicación del hueco
entre procedencia y corrección; la integración externa sigue pendiente.

## Validación que todavía falta

El mapa competitivo valida diferenciación conceptual, no mercado. La hipótesis
de valor sigue abierta hasta obtener una evidencia específica:

- un equipo financia una campaña sobre su propia política;
- un consumidor dice que usaría el estado de esa campaña para asignar permisos o
  capital;
- o un tercero implementa un recomputer y ejecuta un challenge.

Una reacción, un like o una opinión general no cuenta.
