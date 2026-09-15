# Caso de uso principal candidato — bounty sobre una política de agente

Estado: **encaje técnico, dominio, reproducción y gas local validados**. El
adaptador de campaña existe como prototipo local y el recorrido completo pasa en
tests. Despliegue, búsqueda amplia y demanda externa todavía no validados.

## La frase

> **Dissent lets an agent put a bounty on its own decision policy. Find one
> valid state that makes the policy break its mandate, and Monad pays you.**

Versión corta:

> **Bug bounties for agent decisions.**

## El objeto que se desafía

No se desafía una opinión de un LLM ni el resultado futuro de una predicción.
Se desafía una propiedad falsable de una versión concreta de una política
determinista.

Ejemplo Alnitak, formulado como una campaña sobre una versión de política:

```text
Policy: Alnitak river policy, version <hash>
Claim: for every valid state in the declared domain, every high-pressure river call satisfies
       exact conditioned equity >= pot price + 15 percentage points
Reward: N MON
Counterexample: one valid state where the policy calls and the inequality fails
```

La mala trayectoria de Alnitak no se presenta como éxito. Es la razón verificable
por la que existe el producto: probar algunos casos no encontró fallos que después
aparecieron operando el agente.

## Puerta 1 cerrada — el mandato y el fallo real

El mandato elegido no se inventó para la demo. La rama `pf3:potoddsini` del bot
exige un margen `_POT_ODDS_MARGIN = 0.15` entre la equity y el precio del bote.
La auditoría histórica conserva esta decisión real:

```text
Hand           Jh Jd
Board          5c 9s 2h 6h 4c
Action         CALL 190
Pot price      27.4170%
Old exact equity                             56.8942%
Exact equity conditioned on shown pressure  32.0046%
Required by the mandate                     42.4170% (= 27.4170% + 15%)
Verdict        violation
Hand result    -340 chips (context only; it does not decide the verdict)
```

El veredicto no depende de que la mano perdiera. Depende de que
`32.0046% < 42.4170%`.
La misma medición contiene un control positivo dentro del mismo dominio de
river: `4hAh` en `Ac 3h 6d Th 8c` siguió pagando; la equity exacta pasó de
73.0375% a 77.2441% frente a un precio de 25% (mínimo exigido: 40%). Por tanto,
el ejemplo no
equivale a «toda llamada pierde» ni a «perdió, luego decidió mal».

Fuentes locales de la afirmación:

- `poker-bot-repo/strategy.py`, commit `84dbf79`, para la regla y el margen;
- `DIAGNOSTICO_20260909/analisis.log`, para el recibo reconstruido de `JhJd`;
- `medir_rango2.log` y el replay `cmtp8lf87jihi15he5bxzwvmc`, para el control
  de river `4hAh`.

Antes de publicar el repositorio se debe incorporar una fixture mínima derivada,
sin credenciales ni datos ajenos innecesarios, para que esta evidencia no dependa
de rutas privadas de la computadora.

## Una recompensa por versión, no por decisión

La unidad comercial propuesta es una versión de política. El agente financia una
sola recompensa sobre una afirmación universal y los retadores buscan fuera de
cadena cualquier estado permitido que la contradiga. No hace falta demostrar que
el estado ya ocurrió: si la política afirma que la propiedad vale para todo su
dominio, un estado válido basta para refutarla.

La mano `JhJd` es especialmente útil porque demuestra que el contraejemplo no es
puramente imaginario: ocurrió antes de que la política fuera corregida. El
veredicto, sin embargo, depende del estado y de la regla, no de su procedencia ni
del resultado económico de aquella mano.

## Cómo cabe en DissentCore sin modificarlo

`inputs` fija la campaña:

- hash y versión de la política;
- identificador del invariante;
- límites del dominio de estados válidos;
- parámetros públicos de la regla.

`evidence` contiene un único estado candidato.

El recomputer puede definir:

```text
recompute(inputs, "")       = 0  // cero violaciones en el conjunto vacío
recompute(inputs, evidence) = 0  // estado válido, no viola
recompute(inputs, evidence) = 1  // estado válido, viola el invariante
```

El compromiso usa `Comparator.AtMost` y `threshold = 0`. Un `1` cruza el límite
y liquida la recompensa. `validateEvidence` comprueba que el estado está bien
formado, no repite cartas, respeta tamaños y pertenece al dominio publicado.

Esto utiliza exactamente la interfaz actual:

- una campaña permanece abierta después de challenges fallidos;
- el primer contraejemplo exitoso la resuelve;
- el commit-reveal evita que otro copie el estado pendiente y se adelante;
- el recomputer, el hash de inputs, el umbral y la política de gas quedan ligados
  al commitment;
- no se necesita cambiar `DissentCore` para probar el caso.

## Por qué alguien pagaría

El comprador no paga por volver a ejecutar una fórmula. Paga por **atraer capacidad
de búsqueda externa** sobre estados que su propio equipo no encontró.

El modelo solo tiene sentido si se cumplen simultáneamente estas condiciones:

1. El espacio de estados válidos es demasiado grande para enumerarlo dentro de
   una transacción y no es trivial agotarlo fuera de cadena.
2. Un estado concreto puede comprobarse de manera determinista dentro del límite
   de gas de Monad.
3. La propiedad representa un mandato con una consecuencia económica concreta.
4. La recompensa supera gas, depósito y coste esperado de buscar.
5. El recomputer y el dominio son elegidos o aprobados por el consumidor, no solo
   por el agente que quiere parecer seguro.

Si cualquiera falla, el caso no necesita Dissent.

## Usuario inicial

Hipótesis, todavía no validada: desarrolladores, marketplaces o vaults que
permiten actuar a políticas deterministas o híbridas y quieren una campaña
pública de adversarial testing antes de aumentar sus permisos o capital.

El consumidor podría exigir:

```text
Esta versión solo recibe el siguiente nivel de capital si mantiene abierta una
campaña Dissent bajo el recomputer aprobado y no aparece un contraejemplo válido.
```

Dissent no debe afirmar que la ausencia de challenges prueba seguridad. Solo
registra que no apareció un contraejemplo pagado durante esa ventana.

## Diferencia frente a vecinos reales

### AgentTrial

Ejecuta trials adversariales planificados, aplica assertions deterministas y
produce recibos firmados. Dissent no debe competir como suite de evaluación:
abre una recompensa permissionless y deja que participantes externos busquen el
estado que rompe una política.

Fuente: <https://github.com/tang-vu/agenttrial>

### Agent Overflow

Publica problemas que un agente no sabe resolver y paga una solución verificada.
Dissent publica una garantía sobre una política que ya pretende actuar y paga el
contraejemplo que invalida esa garantía. Ambos usan la asimetría entre búsqueda y
verificación; no se debe afirmar que no son vecinos.

Fuente: <https://app-blue-gamma-18.vercel.app/for>

### Code4rena / bug bounties

Ya existe un mercado probado para recompensar fallos y pruebas sobre software.
Dissent no inventa el bug bounty. Su apuesta es convertir una propiedad numérica
de la política de un agente en un challenge que se adjudica y liquida onchain sin
un juez humano.

Fuente: <https://code4rena.com/reports/2023-01-blockswap-fv>

### PACE y execution guards

Los guards comprueban una política antes de cada transacción. Dissent no debe
reemplazarlos: busca estados que demuestren que la política o su modelo son
insuficientes. Si el fallo ya puede bloquearse con un chequeo directo y barato,
el guard es la herramienta correcta.

Fuente: <https://arxiv.org/abs/2608.17220>

## La demo de dos minutos

### Acto 1 — el mandato

> Alnitak vX puts a bounty on its decision policy: every high-pressure river
> call must clear the price by at least 15 points.

En pantalla: hash de versión, dominio, invariante
`equity >= price + 15 puntos` y recompensa.

### Acto 2 — la búsqueda

Un contador genera estados permitidos fuera de cadena. No se presenta como IA:
es búsqueda adversarial. Aparece `JhJd`, el mismo estado de una decisión
histórica del bot.

### Acto 3 — la reproducción

Monad recibe ese único estado, valida que es una mano posible, ejecuta la política
registrada y muestra:

```text
POLICY ACTION       CALL
CONDITIONED EQUITY  32.0%
REQUIRED MARGIN     42.4%  (27.4% price + 15%)
INVARIANT           BROKEN
```

### Acto 4 — la consecuencia

La recompensa se mueve al challenger y la versión queda `Challenged`.

> **The challenger did not argue with the agent. It produced one state the
> policy could not survive. Monad replayed it and paid the proof.**

### Cierre

La vista se aleja de Alnitak y muestra adaptadores posibles como trabajo futuro,
no como integraciones terminadas:

- treasury policy invariant;
- autonomous procurement constraint;
- deterministic execution policy.

## Qué hace inolvidable el caso

- El antagonista no es otro LLM: es un contraejemplo reproducible.
- El agente malo no avergüenza el proyecto; demuestra por qué probar agentes es
  distinto de enseñar una demo feliz.
- La animación principal es una regla que se rompe y dinero que cambia de dueño.
- El recibo de Monad es el final de la historia, no una decoración técnica.

## Estado de las puertas

1. **Invariante — cerrado:** una llamada de river bajo presión alta debe cumplir
   `exact conditioned equity >= pot price + 15 puntos`; `JhJd` es una violación
   histórica y `4hAh` es el control positivo dentro del mismo dominio.
2. **Dominio — cerrado como prototipo:** cartas, cantidades y traza agresiva
   ordenada; la presión se deriva y `bet/small` queda explícitamente fuera.
3. **Reproducción retrospectiva — cerrada:** Python independiente y Solidity
   coinciden. El exportador recorrió 2.184 replays, reconstruyó 11 estados
   elegibles y el scanner encontró tres contraejemplos sin recibir los ganadores
   de antemano. Falta validación prospectiva sobre replays posteriores.
4. **Gas — cerrado localmente:** 17.141.001 para recompute y 17.267.473 para el
   reveal completo con un cap de 20M. `txRequired=20.972.966`; recompensa mínima
   de referencia `2,1172966 MON` a 100 gwei. Falta medición del despliegue real
   en testnet.
5. **Valor externo:** obtener al menos una respuesta de un constructor de agentes
   sobre si abriría una recompensa para una propiedad de su política. Una reacción
   o un like no cuentan.

## Veredicto actual

- **Encaje con DissentCore:** sí, por lectura de la interfaz y del ciclo de estados.
- **Historia auténtica:** sí, el mandato, la violación y el control salen del
  código y de mediciones históricas de Alnitak.
- **Diferencia absoluta / mundialmente única:** no demostrada.
- **Demanda:** no demostrada.
- **Segundo adaptador:** prototipo local implementado; todavía no revisado,
  commiteado ni desplegado.
