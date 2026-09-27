# Dissent web demo

Interfaz estática y de solo lectura para la ejecución de **Policy Bounty**
con un recomputer activo en `RecomputerRegistry` sobre Monad Mainnet.
No usa wallet, claves, backend ni dependencias JavaScript.

La página consulta directamente `https://rpc.monad.xyz` y comprueba:

- los cuatro recibos de la demo (`status = 1`, bloque y contrato esperados):
  commitment, sello, reveal y retiro;
- el evento `ChallengeSucceeded` emitido por el core para este commitment y
  challenger, con `newValue = 1`, `threshold = 0` y payout de 3,1 MON;
- que el commitment terminó `Challenged`;
- el evento `Withdrawn` exacto del challenger por 3,1 MON.

La verificación es local a esta campaña. No exige que los créditos o el escrow
globales del contrato sigan en cero: otras campañas pueden cambiar esos saldos
después sin invalidar los recibos ni el resultado de este commitment.

La reproducción animada usa datos fijos del caso histórico. El veredicto,
los recibos y la explicación del resultado permanecen ocultos hasta el último
paso del replay. Entonces el panel hace lecturas RPC de solo lectura; también
pueden repetirse con «Refresh». El recibo de la revelación decisiva tiene un
enlace directo a MonadVision; los cuatro recibos completos están en una sección
desplegable. Una lectura fallida no se muestra como prueba confirmada. El caso
anterior de equity está documentado separadamente en `docs/LIVE_DEMO.md`;
no se mezclan sus porcentajes ni sus transacciones con esta campaña.

El replay también muestra el resultado económico completo: las cuatro
transacciones Mainnet costaron `3.138113844 MON` en gas. El challenger pagó
`3.088395576 MON`, recibió la recompensa de `3 MON` y recuperó su depósito de
`0.1 MON`; por tanto terminó `0.088395576 MON` por debajo de su saldo inicial.
Es una medición de este recorrido, no una tarifa futura ni una garantía de
rentabilidad.

Servir localmente desde la raíz del repo:

```powershell
node web/serve.mjs
```

Abrir `http://127.0.0.1:4173`.

Probar la verificación de eventos sin red:

```powershell
node --test web/proof.test.mjs
```

## Publicación

`.github/workflows/pages.yml` publica únicamente esta carpeta mediante GitHub
Pages. Mientras el repositorio sea privado en un plan sin Pages para repositorios
privados, el job se omite. Al hacer público el repositorio, el push a `master`
vuelve a habilitarlo; GitHub Pages debe tener como fuente **GitHub Actions**.
La página pública vigente se sirve desde Vercel.

La UI no afirma que Dissent verifique la verdad de las entradas. Muestra una
propiedad concreta de la política histórica v1 de Alnitak que se rompió bajo
el modelo de presión del adaptador. El commit vincula el recomputer y el
contrato liquida la refutación bajo esa regla; no se infiere que todos los
agentes o manos se comporten igual. La demanda y la auditoría externa siguen
pendientes.

La mano de ejemplo fue jugada por Alnitak en dev.fun Arena. Dissent es un proyecto
independiente y no está respaldado ni afiliado a dev.fun.
