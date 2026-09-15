# Tesis de valor de Dissent

Estado: **encaje técnico respaldado por fuentes; adopción comercial todavía no
validada**.

## Una frase

**Dissent es un bug bounty para políticas de agentes: el agente publica una
versión, un mandato falsable y una recompensa. Si alguien encuentra un estado
válido que rompe el mandato, Monad lo comprueba y paga.**

Categoría propuesta:

> **Counterexample bounties for agent policies.** Find an allowed state that
> breaks the committed decision boundary, and get paid onchain.

Versión para una demo:

> An agent puts a bounty on its own decision policy. Find one valid state that
> breaks the mandate, and Monad pays you.

## El problema concreto

Los registros de reputación permiten publicar opiniones y puntuaciones, pero una
puntuación no demuestra que el trabajo del agente fuera correcto. El estudio
empírico de ERC-8004 de Xiong et al. encontró feedback rara vez ligado a
interacciones verificables y una alta presencia de comportamiento Sybil en las
tres cadenas estudiadas.

ERC-8004 incluye un `ValidationRegistry` para registrar verificaciones de
terceros. Su propia especificación propone validadores con re-ejecución protegida
por stake, pero deja los incentivos y el slashing fuera del estándar. Dissent
puede ocupar esa capa para el subconjunto de resultados que son numéricos,
deterministas y económicamente importantes.

Fuentes:

- ERC-8004: <https://eips.ethereum.org/EIPS/eip-8004>
- Estudio empírico: <https://arxiv.org/abs/2606.26028>

## Qué compra el usuario

El usuario no compra una fórmula ni una opinión. Compra **búsqueda adversarial
incentivada**:

1. El agente identifica su versión de política, dominio, mandato y recomputer.
2. Deja una recompensa suficiente para respaldar el coste del desafío.
3. Challengers externos buscan dentro del espacio de evidencia permitido.
4. Si alguien presenta un contraejemplo, Dissent ejecuta el método registrado
   dentro de la EVM.
5. El contrato clasifica el resultado y liquida el dinero sin un juez humano,
   un LLM ni un administrador.

La ventaja económica solo existe cuando **encontrar** un contraejemplo exige una
búsqueda no trivial, pero **comprobar** uno concreto es determinista y el daño
evitado supera el bounty y el gas. Dissent sí recalcula el valor base al crear el
compromiso; por tanto, no debe venderse como ahorro de recomputación.

## Usuario inicial

El usuario inicial propuesto es un **marketplace o aplicación que consume
resultados numéricos de agentes desconocidos** y necesita una señal más fuerte
que una reseña o una firma.

Ejemplos de resultados potencialmente compatibles:

- un score de riesgo basado en reglas públicas;
- rendimiento, drawdown o tasa de éxito calculados sobre actividad registrada;
- precio, coste o recompensa calculados bajo una tarifa pública;
- una decisión de riesgo con un espacio grande de escenarios adversos permitidos;
- una salida de optimización para la que encontrar una entrada que viole el
  límite sea difícil, pero comprobar esa entrada sea exacto.

No se afirma que esos mercados hayan aceptado integrar Dissent. Encontrar al
menos un consumidor externo sigue siendo el principal experimento comercial.

## Para qué NO sirve

Dissent no valida:

- opiniones o texto abierto;
- razonamiento privado de un LLM;
- predicciones cuyo resultado solo se conoce en el futuro;
- datos externos sin una procedencia verificable;
- una fórmula elegida unilateralmente como si fuera una verdad universal;
- espacios de challenge tan pequeños que el propio agente pueda agotarlos;
- afirmaciones cuyo valor económico sea menor que el coste del desafío.

El protocolo garantiza la mecánica. El adaptador define la semántica del
dominio. Una integración debe justificar públicamente ambas fronteras.

## Vecinos y diferencia

El mapa comparativo actualizado, incluidos AgentProof, Praxen, AgentMandate,
Agent Bounties y AgentGuard, está en
[`docs/COMPETITIVE_MAP.md`](COMPETITIVE_MAP.md). La revisión no demuestra
inexistencia mundial y no autoriza a presentar Dissent como "el primero".

### AXON ConfidenceBond

AXON ya implementa una fianza económica por veredictos de seguridad: tras un
resultado `SAFE` bloquea OKB y un challenger cobra si el mismo `VerdictLedger`
muestra después `HIGH RISK`. El contrato confirma dos límites relevantes para
la comparación: solo la cuenta `oracle` puede publicar veredictos y
`challenge(token)` no acepta un witness. La adjudicación depende de que el
proveedor publique un cambio posterior.

Dissent no puede diferenciarse diciendo solo "el agente pone dinero detrás de
su resultado". Su diferencia defendible es la **ruta independiente de prueba**:
la política y el recomputer quedan comprometidos antes del challenge; un tercero
presenta un estado; Monad reproduce ese estado y liquida sin esperar una nueva
salida del agente.

Fuente primaria:
<https://github.com/MUTHUKUMARAN-K-1/axon/blob/main/contracts/ConfidenceBond.sol>

### ERC-8004

ERC-8004 registra identidad, feedback y respuestas de validadores. Dissent no
debe reemplazarlo: puede producir una respuesta de validación sustentada por
stake y re-ejecución. La integración todavía no está implementada.

El repositorio oficial advierte que el `ValidationRegistry` sigue bajo
actualización activa. Las direcciones oficiales publicadas para Monad mainnet
incluyen Identity y Reputation; el Validation Registry sí tiene una dirección
común publicada para testnets. Por eso, cualquier conexión inicial debe ser un
contrato opcional y desacoplado: DissentCore no debe depender de una interfaz que
todavía puede cambiar.

Fuente de despliegues y estado:
<https://github.com/erc-8004/erc-8004-contracts>

### UMA Optimistic Oracle

UMA ya permite afirmaciones optimistas, fianzas y disputas. En una disputa, su
arbitraje se escala al DVM y los poseedores de UMA votan. Dissent es más estrecho:
solo acepta dominios con un recomputer determinista y resuelve mediante código en
Monad, no mediante votación.

Fuentes:

- UMA: <https://docs.uma.xyz/>
- Resolución DVM: <https://docs.uma.xyz/using-uma/resolving-disputes>

### AgentBond

AgentBond también reemplaza reputación gratuita por collateral que un agente
puede perder. Su alcance es más amplio: trabajo, escrow, reputación, disputas y
slashing. La diferencia verificable está en la adjudicación. AgentBond declara
que sus disputas las decide un panel de tres verificadores, que el selector del
panel es una clave designada y que los votos incorrectos todavía no se penalizan.
Dissent no resuelve trabajos subjetivos: solo el subconjunto que un recomputer
determinista puede juzgar sin panel.

Fuente: <https://www.agentbond.online/>

### Agent Overflow

Agent Overflow paga por encontrar soluciones a problemas abiertos cuyo
verificador es barato. Dissent empieza después: un agente ya produjo una decisión
que puede mover valor y ofrece una recompensa por encontrar un contraejemplo que
la rompa. La asimetría búsqueda/verificación es vecina; la diferencia está en el
ciclo de producto y en quién hace la afirmación.

La dirección del incentivo también cambia:

- Agent Overflow: **pregunta → bounty → solución correcta**.
- Dissent: **salida del agente → garantía → contraevidencia**.

Fuente: <https://app-blue-gamma-18.vercel.app/for>

### Attestations firmadas

Una firma prueba quién emitió una cifra y que no fue modificada. No prueba que la
cifra sea correcta. Dissent busca cubrir esa segunda pregunta cuando el dominio
permite re-ejecución determinista.

## Primer adaptador y producto general

Alnitak es el primer adaptador y la evidencia de origen. El exportador recorrió
2.184 replays locales, reconstruyó 11 estados dentro del dominio estricto y
encontró tres violaciones históricas distintas. Una de ellas es `JhJd`: su
modelo anterior autorizaba la llamada con 56.8942% de equity exacta; condicionada
por la fuerza mostrada, la cifra era 32.0046% y no alcanzaba el mínimo de
42.4170% exigido por su propia regla. Otro caso real, `4hAh`, conserva la
llamada: 77.2441% frente a un mínimo de 40%. El veredicto no se deduce de ganar
o perder. La medición completa y sus límites están en
[`HISTORICAL_CORPUS_AUDIT.md`](HISTORICAL_CORPUS_AUDIT.md).

El `AlnitakRiverRecomputer` desplegado hoy verifica una mano fija bajo tres tiers.
El caso comercial candidato usa un segundo adaptador de campaña que recibe un
estado completo y juzga una propiedad de una versión de política. Ese adaptador
ya existe como prototipo local y pasa el flujo completo, pero todavía no está
revisado, commiteado ni desplegado.

Es una demostración válida del mecanismo, no todavía validación comercial ni
prospectiva. La búsqueda ya no está limitada a dos fixtures, pero la política se
diseñó después de observar parte del corpus. La prueba más fuerte siguiente es
congelar el hash y reportar lo que ocurra en manos posteriores no usadas para el
diseño.

La presentación debe decir **"el primer adaptador viene de un agente operado en
vivo"**, no **"Dissent es una herramienta de póker"**.

## Experimento comercial que falta

Antes de afirmar encaje de mercado hay que obtener al menos una de estas pruebas:

1. Un equipo externo implementa `IRecomputer`.
2. Un marketplace confirma por escrito que consumiría un resultado de Dissent.
3. Un creador de un agente numérico entrega un caso real, sus entradas y su
   fórmula para construir un adaptador conjunto.

Una reacción, un like o una conversación genérica no cuentan como validación.

## Demo de dos minutos

### Acto 1: la promesa

Pantalla limpia. Un agente deja **3 MON** sobre un mandato de su propia política.

> This agent did not ask to be trusted. It funded the search for what it missed.

### Acto 2: el contraejemplo

Un challenger revela `JhJd`, un estado real que el modelo anterior trató mal. La
interfaz muestra solo lo necesario: acción, equity anterior, equity condicionada
y margen exigido.

### Acto 3: el veredicto

Monad re-ejecuta el cálculo. La cifra cambia de **56.9%** a **32.0%**, no alcanza
el 42.4% requerido y el dinero se desplaza visualmente al challenger. Se enlaza el
recibo real.

> No vote. No AI judge. No trusted evaluator. The rule ran again and the proof
> got paid.

### Cierre

Se aleja la cámara del caso de póker y aparecen otros adaptadores posibles.

> Today, one poker policy. Tomorrow, any agent mandate with a deterministic
> counterexample.

## Decisiones de producto derivadas

- No ampliar `DissentCore` hasta validar un segundo dominio.
- No presentar Dissent como verificador universal de IA.
- Priorizar una integración ERC-8004 mínima solo después de confirmar la interfaz
  y el despliegue que se usarán en Monad; mantenerla fuera de `DissentCore`.
- Priorizar en la web el conflicto visible y el movimiento del stake, no la
  documentación técnica.
- Mantener expuestos los límites del protocolo; ocultarlos debilitaría la
  credibilidad de la propuesta.
- Nombrar los vecinos directos: bug bounties y mercados de problemas verificables.
- Defender la diferencia por el objeto que se desafía: una decisión ya emitida
  por un agente que pone su propia garantía detrás del umbral.

## Pregunta de control

Toda nueva función o caso de uso debe responder sí a esta pregunta:

> ¿Existe una decisión usada por otra parte, es no trivial encontrar un
> contraejemplo, puede comprobarse de forma determinista y el fallo controla más
> valor que el coste del desafío?

Si la respuesta es no, ese caso no necesita Dissent.
