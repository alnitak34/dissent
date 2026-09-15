# Estrategia de presentación de Dissent

Estado: **dirección de producto propuesta; el protocolo y el adaptador Alnitak
por salida están desplegados. El bounty de política sigue local y la adopción
externa todavía no está validada**.

## La idea que debe recordar un juez

> An agent puts a bounty on its own decision policy. Find one valid state that
> breaks the mandate, and Monad pays you.

Dissent no decide qué política es buena. Antes de delegarle valor, las partes
aceptan un mandato público y un contrato inmutable que sabe evaluarlo. El agente
deja una recompensa sobre una versión concreta. Retadores externos buscan un
estado válido que rompa el mandato; si lo encuentran, Monad lo reproduce y
liquida la recompensa sin voto, juez humano, LLM ni administrador.

Descripción de categoría para la conversación técnica:

> **Counterexample bounties for agent policies.** The agent publishes the
> boundary and funds an independent search for the state that breaks it.

La palabra **counterexample** no es decorativa. Ya existen productos que ponen
una fianza detrás de un veredicto y pagan si el propio oráculo cambia de opinión.
Dissent define una ruta de prueba independiente: el challenger aporta el estado,
el recomputer comprometido lo reproduce y el pago no depende de que el agente o
su proveedor publiquen un nuevo veredicto.

Frase de contraste para el pitch, respaldada por el contrato público de AXON:

> **A bond says the agent has money at risk. Dissent defines the independent
> proof that can take it.**

## Usuario y valor

### Usuario inicial propuesto

Una aplicación, protocolo o marketplace que deja que una salida numérica de un
agente active una acción valiosa y necesita que terceros busquen casos adversos.

### Por qué pagaría

- **El agente** deposita la recompensa para demostrar que acepta consecuencias
  si su salida no resiste la regla acordada. Eso puede ayudarle a ser elegido.
- **La aplicación** obtiene una vía pública para someter la decisión a escrutinio
  adversarial bajo reglas conocidas.
- **El challenger** busca un contraejemplo porque existe una recompensa verificable.

El modelo solo crea valor cuando el espacio de contraejemplos es difícil de
agotar, un caso presentado se comprueba determinísticamente y una mala decisión
controla más valor que el coste de impugnarla. El contrato ya recalcula el valor
base en `commit`; no existe un ahorro de esa recomputación.

## Encaje con ERC-8004

ERC-8004 crea identidad, reputación y un registro de validación para agentes. La
especificación menciona expresamente la re-ejecución protegida por stake como un
modelo posible y deja los incentivos y el slashing al protocolo de validación.
Dissent encaja en ese hueco: puede convertir una disputa resuelta en una señal
de validación reutilizable por marketplaces y aplicaciones.

La integración debe ser un adaptador opcional. No debe añadirse a
`DissentCore` mientras la interfaz de Validation Registry siga evolucionando.

Fuente: <https://eips.ethereum.org/EIPS/eip-8004>

## La demo inolvidable: 120 segundos

### 0–15 s — El riesgo

Pantalla oscura. Solo aparece:

> ALNITAK REVIEWED ITS OWN POLICY. IT MISSED THREE STATES.

Debajo, una pregunta grande:

> What did your agent forget to test?

Explicación oral: Alnitak ejecutó decisiones durante meses. Sus tests pasaban,
pero aparecieron estados reales que su modelo no había cubierto. Un equipo no
puede saber de antemano qué caso olvidó probar.

### 15–35 s — La garantía

El agente bloquea **3 MON** sobre una versión y un mandato públicos:

> Every high-pressure river call must clear the price by 15 points.

> Alnitak did not publish another trust score. It funded the search for its own
> counterexample.

### 35–60 s — La búsqueda y el contraejemplo

Un contador recorre el corpus histórico real y muestra, sin ocultar el filtro:

> 2,184 replays → 11 eligible states → 3 policy breaks

Después se detiene en una de las tres manos, `JhJd` sobre
`5c 9s 2h 6h 4c`. No mostrar primero hashes ni parámetros de Solidity.
Mostrar la consecuencia humana:

> Alnitak called. Its old model said 56.9%.

### 60–82 s — El momento wow

La equity cambia visualmente de **56.9%** a **32.0%** cuando se aplica la presión
que el rival mostró. La línea exigida queda fija en **42.4%**: precio 27.4% +
margen de seguridad 15%. Los 3 MON se desplazan hacia el challenger y el estado cambia a
`POLICY BROKEN`.

> The challenger did not argue with the agent. It produced one state the policy
> could not survive. Monad replayed it and paid the proof.

El agente no cambia su respuesta ni admite el error durante la escena. Ese es el
punto: la prueba externa basta.

### 82–105 s — Prueba, no teatro

La interfaz consulta Monad Testnet y muestra:

- el challenge y el pago confirmados;
- `Challenged` como estado final;
- escrow y crédito en cero después del retiro;
- enlace a los recibos y contratos verificados.

No recorrer código. El código y los 131 tests son respaldo para preguntas, no
el centro del video.

### 105–120 s — El producto general

Antes de alejar la cámara, aparece el control real `4hAh`: 77.2% frente a un
mínimo de 40%; el mismo verificador lo deja pasar. Esto muestra que Dissent no condena
toda decisión ni juzga por el resultado.

Después la cámara se aleja del póker. Aparecen tres tarjetas, marcadas como casos
compatibles y no como integraciones terminadas:

- public risk rule;
- performance metric from registered activity;
- deterministic price or reward calculation.

Cierre:

> Dissent turns an agent mandate into an open, paid search for the state it
> cannot survive.

## Cambios necesarios en la web

La web actual demuestra el caso, pero empieza explicando el protocolo. Para la
demo debe empezar creando una decisión:

1. Sustituir el primer CTA por **Challenge the claim** o **Reveal the evidence**.
2. Construir una secuencia controlada de tres estados: claim, evidence, payout.
3. Mantener la consulta RPC real como verificación final.
4. Mover direcciones, hashes y explicación de Monte Carlo a detalles secundarios.
5. Mostrar claramente `AGREED RULE`, porque Dissent no inventa verdad universal.
6. Añadir una tarjeta de integración ERC-8004 marcada `next`, no `live`.

## Respuestas a las objeciones difíciles

### "¿Quién confía en la fórmula?"

Nadie tiene que aceptar una fórmula secreta de Dissent. La aplicación elige un
recomputer público antes de contratar al agente. Dissent garantiza que la misma
regla identificada se aplica al compromiso y a la impugnación. La calidad de esa
regla sigue siendo responsabilidad del dominio y debe auditarse.

### "¿Por qué pagaría por esto?"

No se paga por ejecutar una fórmula que el agente ya puede ejecutar. Se paga por
atraer búsqueda externa de un caso que el agente no encontró. Si el espacio es
pequeño o el agente puede agotarlo de forma barata, Dissent no es necesario.

### "¿Es una copia de UMA?"

UMA es un vecino real y debe nombrarse. Sus disputas pueden escalar a un sistema
de resolución por voto. Dissent restringe el problema a cálculos deterministas
que un contrato puede volver a ejecutar en Monad. Esa restricción permite una
resolución por código, pero también reduce los casos compatibles.

### "¿No hacen esto AgentBond o Agent Overflow?"

No son equivalentes y deben nombrarse sin minimizarlos:

- AgentBond asegura trabajos con collateral, pero su disputa actual la decide un
  panel de verificadores. Dissent no necesita panel para el subconjunto que un
  contrato puede recalcular.
- Agent Overflow resuelve una pregunta abierta y paga una solución correcta.
  Dissent empieza con una decisión ya emitida por un agente y paga un
  contraejemplo que cruza su límite.

La diferenciación no es "tenemos stake" ni "tenemos un verifier". Es la unión
de **decisión del propio agente + espacio de challenge explícito + búsqueda
adversarial abierta + pago automático del primer contraejemplo válido**.

Fuentes:

- <https://www.agentbond.online/>
- <https://app-blue-gamma-18.vercel.app/for>

### "¿No hace esto AXON ConfidenceBond?"

AXON es el vecino económico más cercano encontrado y debe nombrarse. Bloquea
OKB detrás de un veredicto `SAFE`; un challenger cobra si, dentro de siete días,
el `VerdictLedger` pasa a mostrar `HIGH RISK`. Pero solo la cuenta `oracle` puede
publicar ese nuevo veredicto y `challenge(token)` no recibe evidencia del
challenger. Por tanto, el pago depende de un cambio posterior del propio oráculo.

Dissent fija desde el inicio qué recomputer, política, dominio y umbral adjudican
la disputa. El challenger aporta un witness y puede cobrar aunque el agente nunca
cambie su salida. Esa independencia es la diferencia; no "tener stake".

Fuente primaria: <https://github.com/MUTHUKUMARAN-K-1/axon/blob/main/contracts/ConfidenceBond.sol>

### "¿Dissent verifica IA?"

No de forma universal. Verifica únicamente afirmaciones numéricas falsables para
las que existe un recomputer determinista, entradas comprometidas y evidencia
con procedencia suficiente.

## Evidencia actual y hueco actual

### Hecho hoy

- protocolo y adaptador Alnitak desplegados en Monad Testnet;
- contratos verificados públicamente;
- recorrido commit → seal → reveal → payout ejecutado onchain;
- web que lee recibos y estado final desde el RPC;
- 131 tests Foundry y 38 tests del bridge en el último estado verificado;
- exportador ejecutado sobre 2.184 replays locales: 11 estados elegibles y 3
  contraejemplos históricos distintos; ver
  [`HISTORICAL_CORPUS_AUDIT.md`](HISTORICAL_CORPUS_AUDIT.md);
- recomputer de campaña local: `QhJs`, `Ac8c` y `JhJd` dan 1; `4hAh` da 0;
  Python y Solidity coinciden en sus valores exactos, y el flujo completo
  acredita 3,1 MON de prueba al challenger;
- recompute 17.141.001 gas y reveal completo 17.267.473 bajo el perfil local
  Monad; `txRequired=20.972.966` con el cap recomendado de 20M.

La ejecución onchain actual refuta una afirmación numérica sobre una mano fija.
No demuestra todavía la campaña sobre una versión de política descrita arriba.

### Todavía no demostrado

- una integración de un equipo externo;
- despliegue testnet del recomputer de campaña y una ejecución pública;
- validación prospectiva sobre replays que no existían cuando se diseñó la
  política; el corpus actual es retrospectivo y no demuestra generalización;
- un comprador que confirme que usaría esta garantía;
- un segundo dominio con entradas y regla propias;
- conexión opcional con ERC-8004 Validation Registry.

No presentar esos cuatro puntos como terminados.

## Siguiente secuencia de trabajo

1. Convertir la web en la escena interactiva claim → evidence → payout sin
   alterar la lectura onchain existente.
2. Preparar una ficha de integración de una página para equipos: qué salida
   sirve, qué deben aportar y qué construimos nosotros.
3. Elegir un solo candidato real y solicitar una respuesta concreta: salida,
   fórmula, procedencia de entradas y valor controlado.
4. Solo si el caso pasa esos cuatro filtros, construir el segundo recomputer.
5. Después, implementar un adaptador ERC-8004 desacoplado y confirmar su interfaz
   contra el despliegue que usará Metropolis.

## Regla para no desviarnos

No se añade un caso de uso porque suene atractivo. Debe responder sí a todo:

1. ¿Otra parte utiliza la cifra?
2. ¿Encontrar un contraejemplo exige una búsqueda no trivial?
3. ¿Un contraejemplo presentado puede comprobarse determinísticamente?
4. ¿Las entradas y la evidencia tienen procedencia verificable?
5. ¿La mala decisión controla más valor que el coste del desafío?

Si una respuesta es no, ese caso no necesita Dissent.
