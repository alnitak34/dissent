# Estrategia de presentación de Dissent

Estado: **guion de trabajo, no inventario técnico vigente**. El Policy Bounty
ya se desplegó y ejecutó en Monad Testnet; ver
[`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md). La adopción externa,
la auditoría y la validación prospectiva siguen pendientes. Las cifras de tests,
capturas y estados de la web mencionados más abajo son instantáneas de cuando
se redactó este guion; deben verificarse antes de grabar o publicar.

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
- enlace a los recibos, direcciones desplegadas y fuentes verificadas; dejar
  claro que `Status: match` no equivale a una auditoría de seguridad.

No recorrer código. El código y la suite son respaldo para preguntas, no
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

## Plan de web escrito antes del replay actual

La lista siguiente conserva las decisiones de diseño originales. Los puntos
2, 3 y 5 están implementados en la web de `master`. El CTA del punto 1 todavía
dice `Replay the completed challenge`; del punto 4, direcciones y recibos sí
quedaron en detalles secundarios, pero la web no contiene una explicación de
Monte Carlo. El punto 6 (tarjeta ERC-8004) sigue siendo una propuesta, **no una
integración live**.

1. Sustituir el primer CTA por **Challenge the claim** o **Reveal the evidence**.
2. Construir una secuencia controlada de tres estados: claim, evidence, payout.
3. Mantener la consulta RPC real como verificación final.
4. Mover direcciones, hashes y explicación de Monte Carlo a detalles secundarios.
5. Mostrar claramente `AGREED RULE`, porque Dissent no inventa verdad universal.
6. Añadir una tarjeta de integración ERC-8004 marcada `next`, no `live`.

## Respuestas a las objeciones difíciles

### "¿Quién confía en la fórmula?"

Nadie tiene que aceptar una fórmula secreta de Dissent. En la arquitectura en
revisión, **el agente solo puede usar un `policyId` aprobado**; el registro fija
la dirección, el `EXTCODEHASH`, el depósito y los límites. La aplicación que vaya
a confiar en el resultado todavía debe revisar esa política: el codehash de una
dirección no inmoviliza la implementación detrás de un proxy ni su storage. La
calidad y estabilidad de la regla siguen siendo responsabilidad del curator y
de quien la integra, y deben auditarse. Esta versión con registro aún no está
desplegada; el replay público corresponde al núcleo anterior.

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

Dissent fija desde el inicio qué policyId, recomputer, política, dominio y umbral adjudican
la disputa. El challenger aporta un witness y puede cobrar aunque el agente nunca
cambie su salida. Esa independencia es la diferencia; no "tener stake".

Fuente primaria: <https://github.com/MUTHUKUMARAN-K-1/axon/blob/main/contracts/ConfidenceBond.sol>

### "¿Dissent verifica IA?"

No de forma universal. Liquida impugnaciones de afirmaciones numéricas según
el recomputer identificado en cada compromiso. Para que el resultado sea una
prueba útil fuera del contrato, quien lo consume debe confiar en que ese
recomputer es correcto, estable y apropiado para los datos y la evidencia.

## Evidencia actual y hueco actual

### Evidencia al 16-09-2026

- núcleo endurecido y `AlnitakPolicyBountyRecomputer` desplegados en Monad Testnet;
- el **nuevo** par de contratos obtuvo `Status: match` en Sourcify y figura
  «Contract Source Code Verified» en MonadVision desde el 16-09-2026;
  los enlaces y jobs están en
  [`POLICY_BOUNTY_DEPLOYMENT.md`](POLICY_BOUNTY_DEPLOYMENT.md);
- recorrido commit → sellos → reveal → payout → retiros ejecutado onchain;
- web pública que lee siete recibos y estado final desde el RPC; la rama se
  fusionó a `master` el 20-09-2026 y Vercel muestra el replay actual;
- suites y CI documentados en [`SECURITY_DECISION_ADAPTER_FAULT.md`](SECURITY_DECISION_ADAPTER_FAULT.md);
- exportador ejecutado sobre 2.184 replays locales: 11 estados elegibles y 3
  contraejemplos históricos distintos; ver
  [`HISTORICAL_CORPUS_AUDIT.md`](HISTORICAL_CORPUS_AUDIT.md);
- recomputer de campaña: las fixtures locales `QhJs`, `Ac8c` y `JhJd` dan 1;
  `4hAh` da 0. La ejecución onchain documentada usa `JhJd` y acredita 3,1
  test MON al challenger; no afirmar que los otros casos se ejecutaron onchain;
- recompute 17.141.001 gas y reveal completo 17.267.473 bajo el perfil local
  Monad; `txRequired=20.972.966` con el cap recomendado de 20M.

La ejecución onchain actual refuta una afirmación de **Policy Bounty v1** con un
estado concreto. No demuestra una búsqueda abierta realizada onchain, uso por
terceros ni que la regla generalice a decisiones nuevas.

### Todavía no demostrado

- una integración de un equipo externo;
- ejecución onchain de evidencia rechazada en el núcleo nuevo; aún no consta.
  Un `AdapterFault` concreto por revert en `recompute` sí se ejecutó onchain
  en [`FAULT_PROBE.md`](FAULT_PROBE.md), sin probar todos los tipos de fallo;
- validación prospectiva sobre replays que no existían cuando se diseñó la
  política; el corpus actual es retrospectivo y no demuestra generalización;
- un comprador que confirme que usaría esta garantía;
- un segundo dominio con entradas y regla propias;
- conexión opcional con ERC-8004 Validation Registry.

No presentar estos puntos como terminados.

## Siguiente secuencia de trabajo

1. Revisar que web, README y recibos describan el mismo despliegue; la escena
   claim → evidence → payout ya existe en la rama.
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
