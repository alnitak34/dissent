# Fixtures del puente

`alnitak-river-minimal.json` es una fixture minima derivada de la decision 29
de la mesa publica `cmtr0ktvzxa5q15he4ekev8ub` de dev.fun Arena.

Conserva solamente los campos que `bridge/mano.py` necesita para reconstruir
los 352 bytes enviados al recomputer:

- las cartas de Alnitak y el board;
- el bote y el precio de la llamada;
- dos asientos activos anonimizados;
- la apuesta previa que determina la clase de presion.

No contiene el historial completo, las cartas de los demas participantes, sus
identificadores, sus mensajes ni sus razonamientos. La fixture conserva el
`inputsHash` del caso onchain documentado en `docs/LIVE_DEMO.md`.

Dissent es independiente y no esta respaldado ni afiliado a dev.fun. La
atribucion de la fuente no se presenta como una licencia de redistribucion del
replay original.
