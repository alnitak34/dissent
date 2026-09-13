// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "./IRecomputer.sol";

/// @title DissentCore — apuestas sobre afirmaciones deterministas
/// @notice Un agente afirma que f(entradas) cumple un umbral, escrowea una
///         recompensa en MON, y abre una ventana. Cualquiera puede traer
///         evidencia nueva y, si con esa evidencia el valor cruza el umbral,
///         se lleva la recompensa y su deposito. Si no cruza, pierde el deposito.
///
/// EL CONTRATO NUNCA ACEPTA UN NUMERO DE NADIE
/// Ni del agente ni del retador. Todo valor que decide plata lo calcula este
/// contrato llamando al IRecomputer. Las entradas son datos; los numeros son
/// resultados. De ahi salen las tres decisiones que atraviesan el diseno:
///
///   - NO hay owner, NO hay withdraw() administrativo, NO hay pausa, NO hay
///     proxy. Los unicos caminos por los que sale MON son challenge exitoso,
///     challenge fallido, seal vencido y reclaim vencido, y los cuatro
///     desembocan en `credits`. Nadie puede sacar plata que no le corresponda
///     por una de esas reglas, ni siquiera quien desplego.
///   - El nucleo MIDE en vez de PREGUNTAR. No le pregunta al recalculador
///     cuanto gas necesita: lo mide en el commit y usa esa medicion como techo.
///   - El recalculador se invoca por STATICCALL, consecuencia de declararlo
///     `view` en la interfaz. No puede reentrar escribiendo estado.
///
/// CHALLENGE EN DOS FASES
/// Un challenge de un solo paso es front-runnable: el agente ve la evidencia
/// ganadora en el mempool, la copia con otra billetera y con mas gas, y recupera
/// su propia plata. Con eso la recompensa deja de significar nada. Por eso el
/// retador primero sella keccak256(abi.encode(evidence, salt, msg.sender)) y
/// recien despues revela. Nadie puede copiar lo que no ve.
contract DissentCore {
    // ── constantes de tiempo, en BLOQUES ─────────────────────────────────────
    //
    // REVEAL_DELAY_BLOCKS: cuantos bloques tienen que pasar entre sellar y
    // revelar. Tiene que ser >= 1 o el ataque vuelve: si sellar y revelar
    // pudieran caer en el mismo bloque, un observador del mempool podria sacar
    // la evidencia de la transaccion de revelacion y armar su propio par
    // sellar+revelar delante. Con 5 bloques eso es imposible, y ademas queda
    // margen contra reorgs cortos y contra un productor que retenga un bloque.
    // A un bloque de ~400ms son ~2 segundos: irrelevante frente a una ventana de
    // disputa que se mide en horas.
    uint64 public constant REVEAL_DELAY_BLOCKS = 5;

    // REVEAL_WINDOW_BLOCKS: cuanto dura la posibilidad de revelar. Larga para
    // que un retador con una caida de RPC o un mempool congestionado llegue
    // igual; acotada para que el reclaim del agente no quede de rehen. 7200
    // bloques a ~400ms son ~48 minutos.
    uint64 public constant REVEAL_WINDOW_BLOCKS = 7200;

    // MIN_WINDOW: la ventana de desafio mas corta que acepta commit(), en
    // SEGUNDOS porque windowEnds es un timestamp.
    //
    // ES UNA POLITICA DE PROTOCOLO. No es una garantia criptografica: nada
    // asegura que en una hora alguien vaya a mirar, ni que un retador llegue a
    // sellar. Tampoco es una cifra demostrada empiricamente: no sale de medir
    // cuanto tardan retadores reales en ver un compromiso y sellar. Es un piso
    // elegido por razonamiento, y se puede discutir y cambiar.
    //
    // Lo que SI resuelve es un agujero concreto: sin piso, un agente podia pasar
    // window = 1. Nadie alcanza a sellar, el reclaim sale enseguida y queda un
    // registro que parece robusto y nunca fue disputable.
    //
    // Que cubre: VER el compromiso y SELLAR. Revelar no depende de la ventana:
    // challengeReveal se mide en bloques desde el sello, y un sello vivo bloquea
    // el reclaim aunque windowEnds ya haya pasado. Por eso el piso no suma
    // REVEAL_DELAY_BLOCKS ni REVEAL_WINDOW_BLOCKS.
    //
    // Por que una hora: el retador que tiene que llegar a sellar sufre las mismas
    // fallas que el que tiene que llegar a revelar (RPC caido, mempool
    // congestionado), y para revelar el protocolo le da 7200 bloques, ~48
    // minutos a ~400ms. Darle menos margen para sellar que para revelar seria
    // incoherente; una hora es ese numero redondeado hacia arriba.
    uint64 public constant MIN_WINDOW = 1 hours;

    enum Comparator {
        AtLeast, // el agente afirma value >= threshold
        AtMost // el agente afirma value <= threshold
    }

    enum Status {
        None,
        Open,
        Challenged,
        Reclaimed
    }

    struct Commitment {
        address agent;
        address recomputer;
        bytes32 inputsHash; // keccak256(inputs); los bytes se pasan, no se guardan
        bytes32 domain; // lo que devolvio recomputer.domain() en el commit
        bytes32 actionHash; // la accion declarada; NUNCA entra en la identidad
        int256 threshold;
        int256 baseValue; // CALCULADO por el contrato, jamas recibido
        uint128 reward;
        uint128 deposit; // lo que tiene que poner cada retador
        uint64 windowEnds; // timestamp: hasta cuando se puede SELLAR
        uint64 latestSealBlock; // el sello mas reciente, revelado o no
        uint32 baseGas; // gas MEDIDO del recompute base
        Comparator comparator;
        Status status;
    }

    struct Seal {
        bytes32 sealedHash;
        uint64 blockNumber;
        uint128 deposit;
        bool settled;
    }

    mapping(bytes32 => Commitment) public commitments;
    /// @dev un sello vivo por (compromiso, retador). Varios retadores pueden
    ///      sellar el mismo compromiso a la vez; eso es sano.
    mapping(bytes32 => mapping(address => Seal)) public seals;

    /// @dev patron pull. Nadie recibe MON por push, y no es un adorno: con pagos
    ///      push, un agente que sea un contrato que rechaza MON haria que TODO
    ///      challenge fallido revirtiera -- porque el deposito perdido va al
    ///      agente -- y con eso su compromiso quedaria incuestionable.
    mapping(address => uint256) public credits;

    /// @dev suma de las recompensas vivas mas los depositos sellados sin
    ///      resolver. La invariante del sistema es
    ///      address(this).balance >= escrowed + suma(credits).
    uint256 public escrowed;

    bool private locked;

    // ── eventos ───────────────────────────────────────────────────────────────
    // Cada evento lleva el valor Y el umbral, juntos, ademas de la escala en la
    // que estan expresados. Un log que guarda solo uno de los dos obliga a
    // reconstruir el otro, y reconstruirlo significa volver a correr el codigo de
    // esa epoca: la version exacta, con sus constantes exactas. En cuanto una de
    // las dos cosas cambia -- y cambian -- el historico deja de ser auditable y
    // pasa a ser una coleccion de numeros sin contexto. Guardar los dos cuesta
    // una palabra por evento y conserva la capacidad de responder, meses
    // despues, por que una decision cayo de un lado y no del otro.
    event Committed(
        bytes32 indexed id,
        address indexed agent,
        address indexed recomputer,
        bytes32 inputsHash,
        bytes32 domain,
        int256 threshold,
        Comparator comparator,
        int256 baseValue,
        uint256 scale,
        uint128 reward,
        uint128 deposit,
        uint64 windowEnds,
        uint32 baseGas,
        bytes32 actionHash,
        string action
    );
    event ChallengeSealed(
        bytes32 indexed id, address indexed challenger, bytes32 sealedHash, uint64 blockNumber, uint128 deposit
    );
    event ChallengeSucceeded(
        bytes32 indexed id,
        address indexed challenger,
        int256 newValue,
        int256 threshold,
        uint256 payout,
        bytes32 evidenceHash
    );
    event ChallengeFailed(
        bytes32 indexed id, address indexed challenger, int256 newValue, int256 threshold, bytes32 evidenceHash
    );
    event ChallengeVoided(bytes32 indexed id, address indexed challenger, bytes32 reason);
    event SealExpired(bytes32 indexed id, address indexed challenger, uint128 deposit);
    event Reclaimed(bytes32 indexed id, address indexed agent, uint256 amount);
    event Credited(address indexed who, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);

    // ── errores ───────────────────────────────────────────────────────────────
    error ZeroReward();
    error ZeroDeposit();
    error WindowTooShort(uint64 window, uint64 minWindow);
    /// @dev Un recalculador que no sabe decir en que escala estan sus numeros no
    ///      es usable: sin eso, `threshold` y `baseValue` son digitos sueltos.
    error ZeroScale();
    error BadValue(uint256 sent, uint256 required);
    error CommitmentExists(bytes32 id);
    error UnknownCommitment(bytes32 id);
    error NotOpen(Status status);
    error WindowClosed(uint64 windowEnds);
    error WindowStillOpen(uint64 windowEnds);
    error SealsStillLive(uint64 until);
    error InputsMismatch(bytes32 expected, bytes32 got);
    error BaseDoesNotSatisfyThreshold(int256 baseValue, int256 threshold);
    error EvidenceRejected(bytes32 reason);
    error RecomputerReverted();
    error NoSeal();
    error SealAlreadyExists();
    error TooEarlyToReveal(uint64 notBefore);
    error RevealWindowClosed(uint64 notAfter);
    error SealMismatch();
    error NothingToWithdraw();
    error TransferFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    /// @notice El compromiso entero. El getter automatico del mapping obliga a
    ///         desestructurar catorce campos y eso se rompe con cualquier cambio.
    function getCommitment(bytes32 id) external view returns (Commitment memory) {
        return commitments[id];
    }

    function getSeal(bytes32 id, address challenger) external view returns (Seal memory) {
        return seals[id][challenger];
    }

    // ── identidad ─────────────────────────────────────────────────────────────

    /// @notice Identidad determinista del compromiso. chainid y address(this)
    ///         adentro para que un compromiso de testnet no valga en mainnet ni
    ///         contra un redespliegue. `action` queda AFUERA: es texto de
    ///         presentacion y no puede decidir si dos compromisos son el mismo.
    function computeCommitmentId(
        address agent,
        address recomputer,
        bytes32 inputsHash,
        int256 threshold,
        Comparator comparator,
        uint128 reward,
        uint128 deposit,
        uint64 windowEnds,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid, address(this), agent, recomputer, inputsHash, threshold, comparator, reward, deposit, windowEnds, salt
            )
        );
    }

    /// @notice El sello de un challenge. Ata la evidencia al retador: sin
    ///         msg.sender adentro, un observador podria copiar el hash y
    ///         revelarlo el primero.
    function computeSeal(bytes calldata evidence, bytes32 salt, address challenger) public pure returns (bytes32) {
        return keccak256(abi.encode(evidence, salt, challenger));
    }

    // ── commit ────────────────────────────────────────────────────────────────

    /// @notice El agente publica entradas, umbral, accion y recompensa. El
    ///         contrato calcula el valor base EL MISMO y lo guarda.
    function commit(
        address recomputer,
        bytes calldata inputs,
        int256 threshold,
        Comparator comparator,
        string calldata action,
        uint128 deposit,
        uint64 window,
        bytes32 salt
    ) external payable nonReentrant returns (bytes32 id) {
        if (msg.value == 0) revert ZeroReward();
        if (msg.value > type(uint128).max) revert BadValue(msg.value, type(uint128).max);
        if (deposit == 0) revert ZeroDeposit();
        if (window < MIN_WINDOW) revert WindowTooShort(window, MIN_WINDOW);

        uint128 reward = uint128(msg.value);
        uint64 windowEnds = uint64(block.timestamp) + window;
        bytes32 inputsHash = keccak256(inputs);

        id = computeCommitmentId(
            msg.sender, recomputer, inputsHash, threshold, comparator, reward, deposit, windowEnds, salt
        );
        if (commitments[id].status != Status.None) revert CommitmentExists(id);

        // El valor base lo calcula el contrato, midiendo lo que cuesta.
        uint256 g0 = gasleft();
        (bool ok, int256 baseValue) = _recompute(recomputer, inputs, "", gasleft() - (gasleft() / 64) - 10_000);
        uint256 usado = g0 - gasleft();
        if (!ok) revert RecomputerReverted();
        if (!_satisfies(baseValue, threshold, comparator)) {
            revert BaseDoesNotSatisfyThreshold(baseValue, threshold);
        }

        bytes32 dom = IRecomputer(recomputer).domain();
        // La escala no decide nada -- el nucleo compara valor contra umbral y los
        // dos vienen en la misma unidad por construccion -- pero SIN ELLA el log
        // no se puede leer. Un `baseValue` de 200128647214854111 no significa
        // nada si no consta que son 1e18. Por eso se lee, se exige distinta de
        // cero y se emite: el evento tiene que bastarse solo.
        uint256 sc = IRecomputer(recomputer).scale();
        if (sc == 0) revert ZeroScale();

        commitments[id] = Commitment({
            agent: msg.sender,
            recomputer: recomputer,
            inputsHash: inputsHash,
            domain: dom,
            actionHash: keccak256(bytes(action)),
            threshold: threshold,
            baseValue: baseValue,
            reward: reward,
            deposit: deposit,
            windowEnds: windowEnds,
            latestSealBlock: 0,
            // uint32(usado) solo corre en la rama falsa de
            //   usado > type(uint32).max ? type(uint32).max : uint32(usado)
            // o sea cuando usado <= type(uint32).max (4.294.967.295): no trunca.
            // Ademas usado es gas medido dentro de UNA transaccion, y Monad limita
            // cada transaccion a 30.000.000 de gas, muy por debajo de uint32.max.
            // La saturacion queda como defensa, no como caso esperado.
            // forge-lint: disable-next-line(unsafe-typecast)
            baseGas: usado > type(uint32).max ? type(uint32).max : uint32(usado),
            comparator: comparator,
            status: Status.Open
        });
        escrowed += reward;

        emit Committed(
            id,
            msg.sender,
            recomputer,
            inputsHash,
            dom,
            threshold,
            comparator,
            baseValue,
            sc,
            reward,
            deposit,
            windowEnds,
            commitments[id].baseGas,
            commitments[id].actionHash,
            action
        );
    }

    // ── challenge, fase 1: sellar ─────────────────────────────────────────────

    /// @notice El retador sella su evidencia y paga el deposito. Nadie ve que
    ///         trae hasta que revela.
    function challengeCommit(bytes32 id, bytes32 sealedHash) external payable nonReentrant {
        Commitment storage c = commitments[id];
        if (c.status == Status.None) revert UnknownCommitment(id);
        if (c.status != Status.Open) revert NotOpen(c.status);
        // block.timestamp a proposito: la ventana dura al menos MIN_WINDOW, una
        // hora, y unos segundos de corrimiento del reloj del proponente no
        // cambian quien llega a sellar.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= c.windowEnds) revert WindowClosed(c.windowEnds);
        if (msg.value != c.deposit) revert BadValue(msg.value, c.deposit);

        Seal storage s = seals[id][msg.sender];
        if (s.blockNumber != 0 && !s.settled) revert SealAlreadyExists();

        seals[id][msg.sender] =
            Seal({sealedHash: sealedHash, blockNumber: uint64(block.number), deposit: uint128(msg.value), settled: false});

        // Cualquier sello, se revele o no, empuja la barrera del reclaim. Asi el
        // agente no puede recuperar su recompensa mientras haya un sello que
        // todavia podria revelarse.
        c.latestSealBlock = uint64(block.number);
        escrowed += msg.value;

        emit ChallengeSealed(id, msg.sender, sealedHash, uint64(block.number), uint128(msg.value));
    }

    // ── challenge, fase 2: revelar ────────────────────────────────────────────

    /// @notice El retador revela. Si el valor recalculado cruza el umbral, cobra
    ///         recompensa + deposito. Si no, pierde el deposito, que va al agente.
    function challengeReveal(bytes32 id, bytes calldata inputs, bytes calldata evidence, bytes32 salt)
        external
        nonReentrant
    {
        Commitment storage c = commitments[id];
        if (c.status == Status.None) revert UnknownCommitment(id);

        Seal storage s = seals[id][msg.sender];
        if (s.blockNumber == 0 || s.settled) revert NoSeal();

        uint64 notBefore = s.blockNumber + REVEAL_DELAY_BLOCKS;
        uint64 notAfter = notBefore + REVEAL_WINDOW_BLOCKS;
        if (block.number < notBefore) revert TooEarlyToReveal(notBefore);
        if (block.number > notAfter) revert RevealWindowClosed(notAfter);
        if (computeSeal(evidence, salt, msg.sender) != s.sealedHash) revert SealMismatch();

        uint128 dep = s.deposit;
        s.settled = true;

        // Si otro gano primero, este retador no hizo nada mal: se le devuelve.
        if (c.status != Status.Open) {
            escrowed -= dep;
            _credit(msg.sender, dep);
            emit ChallengeVoided(id, msg.sender, "ALREADY_RESOLVED");
            return;
        }

        if (keccak256(inputs) != c.inputsHash) revert InputsMismatch(c.inputsHash, keccak256(inputs));

        (bool okEv, bytes32 reason) = IRecomputer(c.recomputer).validateEvidence(inputs, evidence);
        if (!okEv) revert EvidenceRejected(reason);

        // Techo de gas MEDIDO, no declarado. Como el recompute base ya corrio con
        // exito en el commit y toda evidencia valida es a lo sumo tan cara como
        // el, si el commit entro, todo challenge valido entra.
        uint256 cap = uint256(c.baseGas) * 2 + 200_000;
        (bool ok, int256 newValue) = _recompute(c.recomputer, inputs, evidence, cap);
        if (!ok) revert RecomputerReverted();

        bytes32 evHash = keccak256(evidence);

        if (!_satisfies(newValue, c.threshold, c.comparator)) {
            // cruza el umbral: el retador tenia razon
            c.status = Status.Challenged;
            uint256 payout = uint256(c.reward) + uint256(dep);
            escrowed -= payout;
            _credit(msg.sender, payout);
            emit ChallengeSucceeded(id, msg.sender, newValue, c.threshold, payout, evHash);
        } else {
            // no cruza: el compromiso sigue vivo y el deposito va al agente
            escrowed -= dep;
            _credit(c.agent, dep);
            emit ChallengeFailed(id, msg.sender, newValue, c.threshold, evHash);
        }
    }

    /// @notice Un sello que vencio sin revelarse. El deposito se PIERDE y va al
    ///         agente. Cualquiera puede llamarla.
    /// @dev Por que se pierde y no se devuelve, en orden de peso:
    ///      1. Si fuera devolvible, sellar seria gratis salvo el gas, y un
    ///         griefer sellaria una y otra vez para empujar el reclaim del
    ///         agente. La perdida le pone precio a esa molestia.
    ///      2. El deposito es exactamente la fianza por presentarse. Quien sella
    ///         y no revela, en el unico sentido observable, tomo una posicion y
    ///         la abandono.
    ///      3. Si fuera devolvible, el retador tendria una OPCION GRATIS: sellar,
    ///         mirar la cadena, y decidir si revela segun lo que vea. La perdida
    ///         convierte el sello en un compromiso, que es todo el punto.
    ///      El costo de esta eleccion es real y no lo escondo: un retador honesto
    ///      que sufra una caida de RPC pierde su deposito. Contra eso esta la
    ///      ventana de revelacion de 7200 bloques.
    function sweepExpiredSeal(bytes32 id, address challenger) external nonReentrant {
        Commitment storage c = commitments[id];
        if (c.status == Status.None) revert UnknownCommitment(id);
        Seal storage s = seals[id][challenger];
        if (s.blockNumber == 0 || s.settled) revert NoSeal();

        uint64 notAfter = s.blockNumber + REVEAL_DELAY_BLOCKS + REVEAL_WINDOW_BLOCKS;
        if (block.number <= notAfter) revert TooEarlyToReveal(notAfter);

        uint128 dep = s.deposit;
        s.settled = true;
        escrowed -= dep;
        _credit(c.agent, dep);
        emit SealExpired(id, challenger, dep);
    }

    // ── reclaim ───────────────────────────────────────────────────────────────

    /// @notice Vencida la ventana y sin sellos vivos, el agente recupera su MON.
    ///         Cualquiera puede llamarla: el destino es la direccion guardada, no
    ///         msg.sender, asi que el agente no depende de estar vivo para que el
    ///         sistema avance.
    function reclaim(bytes32 id) external nonReentrant {
        Commitment storage c = commitments[id];
        if (c.status == Status.None) revert UnknownCommitment(id);
        if (c.status != Status.Open) revert NotOpen(c.status);
        // block.timestamp a proposito: adelantar unos segundos el reclaim no le
        // quita a nadie una ventana de al menos una hora, y un sello hecho a
        // tiempo lo sigue bloqueando por bloques.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < c.windowEnds) revert WindowStillOpen(c.windowEnds);

        uint64 until = c.latestSealBlock + REVEAL_DELAY_BLOCKS + REVEAL_WINDOW_BLOCKS;
        if (c.latestSealBlock != 0 && block.number <= until) revert SealsStillLive(until);

        c.status = Status.Reclaimed;
        uint128 amount = c.reward;
        escrowed -= amount;
        _credit(c.agent, amount);
        emit Reclaimed(id, c.agent, amount);
    }

    // ── la unica salida de MON ────────────────────────────────────────────────

    function withdrawCredit() external nonReentrant {
        uint256 amount = credits[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        credits[msg.sender] = 0; // efecto antes de la interaccion
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        if (!sent) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    // ── internas ──────────────────────────────────────────────────────────────

    function _credit(address who, uint256 amount) private {
        credits[who] += amount;
        emit Credited(who, amount);
    }

    function _satisfies(int256 value, int256 threshold, Comparator comparator) private pure returns (bool) {
        return comparator == Comparator.AtLeast ? value >= threshold : value <= threshold;
    }

    /// @dev STATICCALL con techo de gas. Devuelve ok=false en vez de burbujear el
    ///      revert, para que el nucleo decida que hacer en vez de morir con el
    ///      adaptador.
    function _recompute(address recomputer, bytes memory inputs, bytes memory evidence, uint256 gasCap)
        private
        view
        returns (bool ok, int256 value)
    {
        bytes memory data = abi.encodeWithSelector(IRecomputer.recompute.selector, inputs, evidence);
        (bool success, bytes memory ret) = recomputer.staticcall{gas: gasCap}(data);
        if (!success || ret.length < 32) return (false, 0);
        value = abi.decode(ret, (int256));
        ok = true;
    }

    /// @dev Sin receive() ni fallback(): a este contrato no se le manda MON suelto.
    ///      La unica forma de que entre plata es commit() o challengeCommit().
}
