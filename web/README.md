# Dissent web demo

Interfaz estática y de solo lectura para la ejecución de **Policy Bounty**
registrada en [`docs/POLICY_BOUNTY_LIVE_RUN.md`](../docs/POLICY_BOUNTY_LIVE_RUN.md).
No usa wallet, claves, backend ni dependencias JavaScript.

La página consulta directamente `https://testnet-rpc.monad.xyz` y comprueba:

- los siete recibos de la demo (`status = 1`, bloque y contrato esperados),
  incluido el primer sello vencido y su liquidación;
- el evento `ChallengeSucceeded` emitido por el core para este commitment y
  challenger, con `newValue = 1`, `threshold = 0` y payout de 3,1 test MON;
- que el commitment terminó `Challenged`;
- los eventos `Withdrawn` exactos del challenger (3,1 test MON) y del agente
  (0,1 test MON) en los dos recibos registrados.

La verificación es local a esta campaña. No exige que los créditos o el escrow
globales del contrato sigan en cero: otras campañas pueden cambiar esos saldos
después sin invalidar los recibos ni el resultado de este commitment.

La reproducción animada usa datos fijos del caso histórico. El veredicto,
los recibos y la explicación del resultado permanecen ocultos hasta el último
paso del replay. Entonces el panel hace lecturas RPC de solo lectura; también
pueden repetirse con «Refresh». El recibo de la revelación decisiva tiene un
enlace directo a MonadVision; los siete recibos completos están en una sección
desplegable. Una lectura fallida no se muestra como prueba confirmada. El caso
anterior de equity está documentado separadamente en `docs/LIVE_DEMO.md`;
no se mezclan sus porcentajes ni sus transacciones con esta campaña.

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
Pages. El workflow se ejecuta al hacer push a `master`, pero GitHub Pages debe
tener como fuente **GitHub Actions** en la configuración del repositorio.

La UI no afirma que Dissent verifique la verdad de las entradas. Muestra una
propiedad concreta de la política histórica v1 de Alnitak que se rompió bajo
el modelo de presión del adaptador. El commit vincula el recomputer y el
contrato liquida la refutación bajo esa regla; no se infiere que todos los
agentes o manos se comporten igual. La demanda y la auditoría externa siguen
pendientes.

La mano de ejemplo fue jugada por Alnitak en dev.fun Arena. Dissent es un proyecto
independiente y no está respaldado ni afiliado a dev.fun.
