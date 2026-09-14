# Dissent web demo

Interfaz estática y de solo lectura para la ejecución completa registrada en
`docs/LIVE_DEMO.md`. No usa wallet, claves, backend ni dependencias JavaScript.

La página consulta directamente `https://testnet-rpc.monad.xyz` y comprueba:

- los cuatro recibos de la demo (`status = 1`);
- que el commitment terminó `Challenged`;
- que el crédito del challenger quedó en cero después de retirarlo;
- que el escrow pendiente quedó en cero.

Servir localmente desde la raíz del repo:

```powershell
node web/serve.mjs
```

Abrir `http://127.0.0.1:4173`.

La UI no afirma que Dissent verifique la verdad de las entradas. Muestra el caso
preciso que el protocolo sí demuestra: una afirmación numérica fue comprometida,
una evidencia válida cambió el cálculo determinista, el umbral se cruzó y el pago
se liquidó sin intervención administrativa.
