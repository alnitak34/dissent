# Auditoría de veracidad de la demo

Estado de la revisión: **15 de septiembre de 2026**.

**Archivo histórico, no estado vigente.** El 16 de septiembre se desplegaron
`DissentCore` endurecido y `AlnitakPolicyBountyRecomputer`, se completó una
refutación en Monad Testnet y la web de la rama
`security-no-payable-adapter-fault` pasó a verificar sus siete transacciones.
Esta auditoría conserva la foto y las decisiones **anteriores** a ese recorrido;
para el estado actual, ver [`POLICY_BOUNTY_LIVE_RUN.md`](POLICY_BOUNTY_LIVE_RUN.md)
y [`../web/README.md`](../web/README.md). La página publicada desde `master`
puede seguir mostrando la versión anterior hasta fusionar y publicar la rama.

Objetivo: impedir que la interfaz atribuya al despliegue actual una campaña de
política que todavía solo existe localmente. La página pública debe distinguir
el caso onchain ya ejecutado del producto que se pretende presentar.

## Verdad onchain actual

La web consulta recibos reales de Monad Testnet para una disputa terminada:

- una afirmación sobre una mano fija;
- `inputs` contiene esa mano y su estado;
- la evidencia es un tier permitido (`OVERBET`);
- el recomputer desplegado cambia la equity de 68,57% a 17,70%;
- el umbral fijo es 36,29%;
- el contrato acredita y permite retirar 3,1 test MON.

Esto está respaldado por [`LIVE_DEMO.md`](LIVE_DEMO.md) y por los cuatro recibos
que `web/app.js` consulta. Demuestra commit, seal, reveal, recompute y settlement.
No demuestra una búsqueda abierta sobre todos los estados de una versión de
política.

## Producto nuevo commiteado localmente

`AlnitakPolicyBountyRecomputer` cambia la unidad del challenge:

- una recompensa por versión de política, no por mano;
- `inputs` fija el hash de la especificación y el margen;
- el challenger aporta un estado completo como witness;
- el recomputer decide si ese estado rompe el mandato;
- el corpus histórico aporta 2.184 replays, 11 estados elegibles y tres
  contraejemplos.

Este adaptador pasó la revisión y las suites locales y quedó guardado en el
commit local `dd8495c`. Todavía no se ha enviado al remoto ni desplegado. No
existen recibos públicos de una campaña de política.

## Desajustes de la web actual

| Elemento | Lo que muestra | Lo que realmente prueba | Corrección para la demo final |
| --- | --- | --- | --- |
| Título | `Bug bounties for agent decisions` | Describe una categoría amplia que AXON y otros vecinos pisan parcialmente. | Usar `Counterexample bounties for agent policies`. |
| Hero | `An agent says 68.57%` | Una salida de una mano fija. | Abrir con una versión y un mandato: `Every high-pressure river call must clear price + 15 points`. |
| Regla | `equity ≥ 36.29%` | Umbral fijo de un compromiso. | Mostrar el límite dinámico del witness: `27.4% price + 15% = 42.4%`. |
| Evidencia | `OVERBET` | El challenger selecciona uno de tres tiers pre-registrados. | Revelar el estado completo `JhJd / 5c 9s 2h 6h 4c` y la traza que deriva la presión. |
| Cambio | 68.57% → 17.70% | Dos evaluaciones de la misma mano bajo rangos permitidos. | Mostrar `old gate 56.9%` frente a `conditioned 32.0%`; explicar que 32.0% rompe 42.4%. |
| Recibos | Cuatro transacciones reales | Solo la disputa antigua. | Mantenerlos como `Original protocol proof` hasta que existan recibos del nuevo adaptador; después reemplazarlos. |
| Generalización | Texto de counterexample | La cadena no recorrió una política completa. | Mostrar la búsqueda offchain separada: `2,184 → 11 → 3`; Monad verifica únicamente el witness ganador. |
| Independencia | Implícita | No se contrasta con bonds dependientes del emisor. | Añadir: `The agent never changed its answer. The external proof was enough.` |

## Secuencia final que sí sería verdadera

1. **Policy funded:** Alnitak fija el hash de v1, el dominio, el mandato y 3 test
   MON.
2. **Open search:** el contador reproduce el barrido histórico
   `2.184 → 11 → 3` sin insinuar que la EVM enumeró el corpus.
3. **Witness sealed:** se oculta el estado completo para evitar copia.
4. **Witness revealed:** aparece `JhJd`; el gate antiguo autoriza con 56,9%, la
   equity condicionada es 32,0% y el mínimo es 42,4%.
5. **Independent settlement:** Monad reproduce ese único estado y acredita la
   recompensa. Alnitak no publica un veredicto nuevo ni admite el error.
6. **Receipts:** la UI comprueba el compromiso, el reveal, el estado
   `Challenged` y el retiro contra el RPC público.

## Puerta antes de cambiar la web pública

No reemplazar la demo actual por la narrativa de campaña hasta completar:

1. ~~revisión técnica del nuevo recomputer y sus inputs~~ — completada con 131
   tests Foundry y 38 tests Python;
2. ~~commit explícitamente autorizado~~ — `dd8495c` local;
3. despliegue en Monad Testnet;
4. recorrido real commit → seal → reveal → payout;
5. registro de direcciones, commitment y recibos;
6. actualización de las lecturas RPC de `web/app.js`.

Hasta entonces, la web antigua puede seguir como evidencia del protocolo, pero
no debe presentarse como la campaña de política terminada.
