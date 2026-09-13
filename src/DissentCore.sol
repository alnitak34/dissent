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
    // A ~300ms por bloque (tiempo de bloque nominal de Monad) son ~1,5 segundos:
    // irrelevante frente a una ventana de disputa que se mide en minutos/horas.
    uint64 public constant REVEAL_DELAY_BLOCKS = 5;

    // REVEAL_WINDOW_BLOCKS: cuanto dura la posibilidad de revelar. Larga para
    // que un retador con una caida de RPC o un mempool congestionado llegue
    // igual; acotada para que el reclaim del agente no quede de rehen. 7200
    // bloques a ~300ms son ~36 minutos NOMINALES (el tiempo real depende del
    // tiempo de bloque de la red; la ventana esta expresada en bloques).
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
    // congestionado), y para revelar el protocolo le da 7200 bloques, ~36
    // minutos nominales a ~300ms. Darle menos margen para sellar que para revelar
    // seria incoherente; una hora es ese numero redondeado hacia arriba.
    uint64 public constant MIN_WINDOW = 1 hours;

    // ── modelo de gas del challenge (constantes medidas; ver diseño) ──────────
    // Limite de gas POR TRANSACCION de Monad (no es el limite de bloque, que es
    // otro). La transaccion completa del reveal tiene que caber aca.
    uint256 public constant MONAD_TX_GAS_LIMIT = 30_000_000;
    // Intrinseco de transaccion (21000) y costo por byte de calldata (16, peor
    // caso, todo no-cero). Para acotar el intrinseco del reveal en el chequeo de
    // commit: ese gas se gasta ANTES de que challengeReveal vea gasleft().
    uint256 private constant TX_INTRINSIC_BASE = 21_000;
    uint256 private constant CALLDATA_BYTE_GAS = 16;
    // Overhead EN-CONTRATO desde la entrada de challengeReveal hasta el chequeo
    // del piso (SLOADs del commitment/seal, chequeos de ventana, EvidenceTooLong,
    // computeSeal, SealMismatch, el SSTORE de settled y la rama void). Medido
    // ~17.5k hasta SealMismatch + el SSTORE de settled; redondeado con margen. No
    // esta disponible en gasleft() cuando se evalua el piso.
    uint256 private constant ENTRY_OVERHEAD = 80_000;
    // Precio de gas de REFERENCIA para el respaldo economico. 100 MON-gwei es el
    // piso de base fee de Monad al momento de este diseño; NO es una constante
    // garantizada para siempre (si el piso de Monad sube, un redespliegue con otro
    // valor). El precio efectivo del compromiso se fija al commit como
    // max(REFERENCE_GAS_PRICE, block.basefee) y no cambia despues.
    uint256 public constant REFERENCE_GAS_PRICE = 100 gwei;
    // Gas de un challengeCommit completo (medido ~150k incl. intrinseco) + margen.
    // Entra en el respaldo porque el retador tambien paga el sello.
    uint256 public constant CHALLENGE_COMMIT_GAS = 200_000;
    // Longitud maxima de evidence aceptada por el protocolo. Mantiene los
    // coeficientes lineales validos (medidos lineales hasta 512 KiB) y acota el
    // peor caso de prework. Cada compromiso declara su propio maxEvidenceLen <= este.
    uint256 public constant MAX_EVIDENCE_LEN = 131072; // 128 KiB
    // Overhead fijo de un STATICCALL al adaptador. Medido en el perfil Monad:
    // ~10.4k en caliente, ~18.6k en FRIO (la 1ra llamada, validate, accede a la
    // direccion en frio). 22_000 = 18.559 medido + ~14% de margen (mismo criterio
    // con que se redondeo 10,5k->12k). C_CALL cubre EXCLUSIVAMENTE el overhead de
    // la llamada; el margen ceil(limit/63) de _deliver cubre EXCLUSIVAMENTE la
    // regla EIP-150. Son reservas independientes.
    uint256 private constant C_CALL = 22_000;
    // Liquidacion posterior (credito reward+deposito + evento), medida ~143k + margen.
    uint256 private constant SETTLE_RESERVE = 250_000;
    // Prework EN-CONTRATO (SLOADs, aritmetica), medido; NO incluye el intrinseco
    // de la transaccion (ese gas ya se gasto cuando se evalua gasleft()).
    uint256 private constant PREWORK_RESERVE = 150_000;
    // Coeficientes de gas por byte, como enteros con denominador 100 y ceilDiv,
    // para no truncar hacia abajo. Medidos: keccak(inputs)=0.19, computeSeal=2.62,
    // abi.encode de args por llamada=2.43 (aplica x2: validate y recompute).
    uint256 private constant K_INPUTS_NUM = 19;
    uint256 private constant K_SEAL_NUM = 262;
    uint256 private constant K_ENCODE_NUM = 243;
    uint256 private constant K_DEN = 100;

    enum Comparator {
        AtLeast, // el agente afirma value >= threshold
        AtMost // el agente afirma value <= threshold
    }

    enum Status {
        None,
        Open,
        Challenged,
        Reclaimed,
        Faulted // el adaptador incumplio su interfaz con el gas prometido
    }

    /// @notice En que fase fallo el adaptador, para el evento AdapterFaulted.
    enum Phase {
        VALIDATION,
        RECOMPUTE
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
        uint32 recomputeGasLimit; // techo declarado del recompute; parte de la identidad
        uint32 validateGasLimit; // techo declarado del validateEvidence; parte de la identidad
        uint32 maxEvidenceLen; // largo maximo de evidence aceptado; parte de la identidad
        // Precio de gas fijado al commit = max(REFERENCE_GAS_PRICE, block.basefee).
        // uint256 y sin cast: un precio de gas no tiene una cota superior segura
        // que asumir, asi que evitamos cualquier truncamiento. Parte de la identidad.
        uint256 effectiveGasPrice;
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
    /// @notice El adaptador incumplio su interfaz (revert / OOG / returndata no
    ///         canonico) teniendo el gas prometido. Es un FALLO TECNICO del
    ///         adaptador que eligio el agente, NO una refutacion de la afirmacion.
    event AdapterFaulted(bytes32 indexed id, address indexed challenger, Phase phase, uint256 payout);
    /// @notice validateEvidence completo y devolvio (false, reason): la evidencia
    ///         esta malformada para estos inputs. NO es refutacion ni fallo tecnico.
    event ChallengeRejected(bytes32 indexed id, address indexed challenger, bytes32 reason);
    /// @notice La politica de gas del compromiso, tambien parte de su identidad.
    ///         Con estos campos se reconstruye todo: los tres limites, el precio
    ///         efectivo, el gas total respaldado y la recompensa minima respaldada.
    event CommitGasPolicy(
        bytes32 indexed id,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen,
        uint256 effectiveGasPrice,
        uint256 totalGasBacking,
        uint256 minGasBackedReward
    );
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
    error RecomputerReverted();
    error InsufficientChallengeGas();
    error EvidenceTooLong(uint256 len, uint256 max);
    error GasLimitsTooLarge(uint256 floor, uint256 limit);
    error RewardBelowGasBacking(uint256 sent, uint256 required);
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
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen,
        uint256 effectiveGasPrice,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                agent,
                recomputer,
                inputsHash,
                threshold,
                comparator,
                reward,
                deposit,
                windowEnds,
                recomputeGasLimit,
                validateGasLimit,
                maxEvidenceLen,
                effectiveGasPrice,
                salt
            )
        );
    }

    // ── modelo de gas: helpers ─────────────────────────────────────────────────

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        return (a + b - 1) / b;
    }

    /// @dev Gas que hay que tener disponible para ENTREGAR `lim` al adaptador bajo
    ///      EIP-150 (que retiene 1/64) mas el overhead fijo de la llamada.
    function _deliver(uint256 lim) private pure returns (uint256) {
        return lim + _ceilDiv(lim, 63) + C_CALL;
    }

    /// @dev abi.encode de los args de UNA llamada al adaptador (selector+inputs+
    ///      evidence): coste dependiente de longitud, ceilDiv (no trunca abajo).
    function _encodeGas(uint256 inLen, uint256 evLen) private pure returns (uint256) {
        return _ceilDiv(K_ENCODE_NUM * (inLen + evLen), K_DEN);
    }

    /// @dev Costo dependiente de longitud reservado en el piso (trabajo FUTURO al
    ///      punto del piso): keccak(inputs), computeSeal (contado tambien aca como
    ///      sobre-reserva conservadora), y las DOS codificaciones de args.
    function _lengthGas(uint256 inLen, uint256 evLen) private pure returns (uint256) {
        return _ceilDiv(K_INPUTS_NUM * inLen, K_DEN) + _ceilDiv(K_SEAL_NUM * evLen, K_DEN) + 2 * _encodeGas(inLen, evLen);
    }

    /// @notice Gas EN-CONTRATO que challengeReveal necesita disponible en el punto
    ///         del piso. NO incluye el intrinseco de la transaccion ni el overhead
    ///         de entrada (ya gastados al evaluar gasleft()).
    function functionGasFloor(uint256 validateGasLimit, uint256 recomputeGasLimit, uint256 inLen, uint256 evLen)
        public
        pure
        returns (uint256)
    {
        return PREWORK_RESERVE + _lengthGas(inLen, evLen) + _deliver(validateGasLimit) + _deliver(recomputeGasLimit)
            + SETTLE_RESERVE;
    }

    function _round32(uint256 x) private pure returns (uint256) {
        return ((x + 31) / 32) * 32;
    }

    /// @dev Intrinseco del reveal: 21000 + 16/byte del tamaño ABI de
    ///      challengeReveal(bytes32, bytes inputs, bytes evidence, bytes32).
    function _revealIntrinsic(uint256 inLen, uint256 evLen) private pure returns (uint256) {
        uint256 abiBytes = 4 + 128 + 32 + _round32(inLen) + 32 + _round32(evLen);
        return TX_INTRINSIC_BASE + CALLDATA_BYTE_GAS * abiBytes;
    }

    /// @notice Gas TOTAL de la transaccion de reveal: intrinseco + overhead de
    ///         entrada + piso en-contrato. Es lo que tiene que caber en 30M y lo
    ///         que el respaldo economico (otro commit) usa como base.
    function txRequired(uint256 validateGasLimit, uint256 recomputeGasLimit, uint256 inLen, uint256 evLen)
        public
        pure
        returns (uint256)
    {
        return _revealIntrinsic(inLen, evLen) + ENTRY_OVERHEAD
            + functionGasFloor(validateGasLimit, recomputeGasLimit, inLen, evLen);
    }

    /// @notice El precio de gas que se fijaria AHORA: max(REFERENCE_GAS_PRICE,
    ///         block.basefee). Para que frontend/bridge estimen antes del commit.
    ///         El valor onchain al commit es la autoridad.
    /// @dev block.basefee a proposito: define el piso de respaldo, no una ventana
    ///      de tiempo; un corrimiento del reloj no lo afecta.
    // forge-lint: disable-next-line(block-timestamp)
    function effectiveReferenceGasPrice() public view returns (uint256) {
        uint256 bf = block.basefee;
        return bf > REFERENCE_GAS_PRICE ? bf : REFERENCE_GAS_PRICE;
    }

    /// @notice MIN_GAS_BACKED_REWARD: recompensa minima que respalda el gas de una
    ///         refutacion exitosa (reveal + el challengeCommit previo) al precio
    ///         fijado en el commit. NO incluye el deposito: la recompensa cubre el
    ///         gas del retador; su propio deposito simplemente le vuelve cuando gana.
    ///
    ///         Cubre el PRESUPUESTO DE GAS DE REFERENCIA que calcula el protocolo
    ///         (txRequired + CHALLENGE_COMMIT_GAS), NO un gas limit que el retador
    ///         elija declarar. Si el retador manda una tx con un gas limit mayor,
    ///         Monad le cobra ESE valor mayor y Dissent no garantiza la diferencia.
    ///
    ///         NO ES UNA GARANTIA DE RENTABILIDAD. No incorpora la probabilidad p de
    ///         que el retador tenga razon, ni protege contra una suba posterior de
    ///         block.basefee. El valor esperado real del retador es:
    ///             expectedNet = p*reward - (1-p)*deposit - gasCost
    ///         Este piso solo asegura que, al precio de referencia y si el challenge
    ///         triunfa, la recompensa cubre el gas gastado.
    /// @dev Multiplicacion uint256 sin cast: si no cabe, Solidity 0.8 revierte
    ///      (Panic 0x11); nunca satura en silencio.
    function minGasBackedReward(uint256 validateGasLimit, uint256 recomputeGasLimit, uint256 inLen, uint256 evLen)
        public
        view
        returns (uint256)
    {
        uint256 totalGasBacking = txRequired(validateGasLimit, recomputeGasLimit, inLen, evLen) + CHALLENGE_COMMIT_GAS;
        return totalGasBacking * effectiveReferenceGasPrice();
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
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen,
        bytes32 salt
    ) external payable nonReentrant returns (bytes32 id) {
        if (msg.value == 0) revert ZeroReward();
        if (msg.value > type(uint128).max) revert BadValue(msg.value, type(uint128).max);
        if (deposit == 0) revert ZeroDeposit();
        if (window < MIN_WINDOW) revert WindowTooShort(window, MIN_WINDOW);
        if (maxEvidenceLen > MAX_EVIDENCE_LEN) revert EvidenceTooLong(maxEvidenceLen, MAX_EVIDENCE_LEN);

        // FUNCIONAL: la TRANSACCION COMPLETA del peor caso (evidence en
        // maxEvidenceLen) tiene que caber en 30M: intrinseco + entrada + piso, no
        // solo el piso. El economico va en un commit aparte.
        uint256 txWorst = txRequired(validateGasLimit, recomputeGasLimit, inputs.length, maxEvidenceLen);
        if (txWorst > MONAD_TX_GAS_LIMIT) revert GasLimitsTooLarge(txWorst, MONAD_TX_GAS_LIMIT);

        // ECONOMICO: la recompensa tiene que respaldar el gas de una refutacion
        // exitosa (reveal + challengeCommit) al precio fijado en el commit. El
        // deposito NO entra: la recompensa cubre el gas del retador; su deposito le
        // vuelve al ganar. Ver minGasBackedReward: es un piso de gas, NO una
        // garantia de rentabilidad. Multiplicacion uint256 sin cast: si no cabe,
        // revierte (Panic 0x11), no satura.
        uint256 effectiveGasPrice = effectiveReferenceGasPrice();
        uint256 totalGasBacking = txWorst + CHALLENGE_COMMIT_GAS;
        uint256 minReward = totalGasBacking * effectiveGasPrice;
        if (msg.value < minReward) revert RewardBelowGasBacking(msg.value, minReward);

        uint128 reward = uint128(msg.value);
        uint64 windowEnds = uint64(block.timestamp) + window;
        bytes32 inputsHash = keccak256(inputs);

        id = computeCommitmentId(
            msg.sender,
            recomputer,
            inputsHash,
            threshold,
            comparator,
            reward,
            deposit,
            windowEnds,
            recomputeGasLimit,
            validateGasLimit,
            maxEvidenceLen,
            effectiveGasPrice,
            salt
        );
        if (commitments[id].status != Status.None) revert CommitmentExists(id);
        // Politica de gas (identidad + respaldo). Emitido temprano para no apilar
        // con el emit Committed de mas abajo; si el commit revierte luego, el log
        // se descarta con la transaccion.
        emit CommitGasPolicy(
            id, recomputeGasLimit, validateGasLimit, maxEvidenceLen, effectiveGasPrice, totalGasBacking, minReward
        );

        // El valor base lo calcula el contrato, midiendo lo que cuesta, con el
        // MISMO techo que usara el reveal. Si recomputeGasLimit no alcanza para el
        // base, el wrapper falla y el commit revierte: el agente no puede declarar
        // un limite por debajo de lo que su propio adaptador necesita.
        uint256 g0 = gasleft();
        (bool bFault, int256 baseValue) = _safeRecompute(recomputer, inputs, "", recomputeGasLimit);
        uint256 usado = g0 - gasleft();
        if (bFault) revert RecomputerReverted();
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
            recomputeGasLimit: recomputeGasLimit,
            validateGasLimit: validateGasLimit,
            maxEvidenceLen: maxEvidenceLen,
            effectiveGasPrice: effectiveGasPrice,
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

        // Chequeos que dependen SOLO de datos del retador (largo de evidencia y
        // sello). Van antes de settled. Ver la nota de settled mas abajo.
        if (evidence.length > c.maxEvidenceLen) revert EvidenceTooLong(evidence.length, c.maxEvidenceLen);
        if (computeSeal(evidence, salt, msg.sender) != s.sealedHash) revert SealMismatch();

        uint128 dep = s.deposit;
        s.settled = true;

        // VOID: si otro ya resolvio, este retador queda anulado. Se le devuelve el
        // deposito ACA, sin pedirle inputs validos, sin cobrarle el piso de V+R y
        // sin llamar al adaptador. Por eso el void va antes del piso y del keccak.
        if (c.status != Status.Open) {
            escrowed -= dep;
            _credit(msg.sender, dep);
            emit ChallengeVoided(id, msg.sender, "ALREADY_RESOLVED");
            return;
        }

        // SEMANTICA DE settled: cualquier revert a partir de aca deshace settled y
        // solo puede proceder de una falta ATRIBUIBLE AL RETADOR (gas insuficiente,
        // inputs que no coinciden); su fianza queda expuesta al sweep, como debe.
        // Una vez CLASIFICADO AdapterFault o ChallengeRejected NO se revierte
        // deliberadamente: por eso el sello queda liquidado y el agente no puede
        // cosechar el deposito por un fallo del adaptador.
        //
        // Piso total: reserva para keccak(inputs), las dos codificaciones, entregar
        // V y R bajo EIP-150, y liquidar.
        if (gasleft() < functionGasFloor(c.validateGasLimit, c.recomputeGasLimit, inputs.length, evidence.length)) {
            revert InsufficientChallengeGas();
        }
        if (keccak256(inputs) != c.inputsHash) revert InputsMismatch(c.inputsHash, keccak256(inputs));

        // Chequeo inmediato antes del STATICCALL a validate: encode de validate,
        // entrega de V, encode FUTURO de recompute, entrega de R, y liquidacion.
        // Pre-decision (aun no hubo fault ni rejected): revertir aca es gas del retador.
        if (
            gasleft()
                < 2 * _encodeGas(inputs.length, evidence.length) + _deliver(c.validateGasLimit)
                    + _deliver(c.recomputeGasLimit) + SETTLE_RESERVE
        ) revert InsufficientChallengeGas();
        (bool vFault, bool okEv, bytes32 reason) =
            _safeValidateEvidence(c.recomputer, inputs, evidence, c.validateGasLimit);
        if (vFault) {
            // fallo tecnico del adaptador en validacion: paga al retador. NO revert.
            _payFault(id, c, msg.sender, dep, Phase.VALIDATION);
            return;
        }
        if (!okEv) {
            // rechazo canonico: liquida el sello, DEVUELVE el deposito al retador,
            // el compromiso sigue Open, el agente no recibe nada. NO revert.
            escrowed -= dep;
            _credit(msg.sender, dep);
            emit ChallengeRejected(id, msg.sender, reason);
            return;
        }

        // Chequeo inmediato antes del STATICCALL a recompute: su encode, entrega de
        // R, y liquidacion.
        if (gasleft() < _encodeGas(inputs.length, evidence.length) + _deliver(c.recomputeGasLimit) + SETTLE_RESERVE) {
            revert InsufficientChallengeGas();
        }
        (bool rFault, int256 newValue) = _safeRecompute(c.recomputer, inputs, evidence, c.recomputeGasLimit);
        if (rFault) {
            _payFault(id, c, msg.sender, dep, Phase.RECOMPUTE);
            return;
        }

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

    /// @dev Fallo tecnico del adaptador con el gas prometido: el retador cobra
    ///      reward + deposito y el compromiso queda Faulted. El sello ya esta
    ///      settled, asi que sweepExpiredSeal no puede pagarle al agente.
    function _payFault(bytes32 id, Commitment storage c, address who, uint128 dep, Phase phase) private {
        c.status = Status.Faulted;
        uint256 payout = uint256(c.reward) + uint256(dep);
        escrowed -= payout;
        _credit(who, payout);
        emit AdapterFaulted(id, who, phase, payout);
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

    /// @dev STATICCALL a recompute con techo `gasCap`. Copia SOLO 32 bytes de
    ///      returndata y exige que sean exactamente 32 (int256 canonico): un
    ///      returndata enorme no puede expandir la memoria del nucleo ni agotar su
    ///      gas. `faulted` = el adaptador no cumplio (revert, OOG, o size != 32).
    function _safeRecompute(address recomputer, bytes memory inputs, bytes memory evidence, uint256 gasCap)
        private
        view
        returns (bool faulted, int256 value)
    {
        bytes memory data = abi.encodeWithSelector(IRecomputer.recompute.selector, inputs, evidence);
        assembly ("memory-safe") {
            let success := staticcall(gasCap, recomputer, add(data, 0x20), mload(data), 0, 0)
            let good := and(success, eq(returndatasize(), 0x20))
            if good {
                returndatacopy(0, 0, 0x20)
                value := mload(0)
            }
            faulted := iszero(good)
        }
    }

    /// @dev STATICCALL a validateEvidence con techo `gasCap`. Copia SOLO 64 bytes
    ///      y exige returndata de exactamente 64 con un bool canonico (0 o 1).
    ///      `faulted` = el adaptador no cumplio; si no, (ok, reason) es su respuesta.
    function _safeValidateEvidence(address recomputer, bytes memory inputs, bytes memory evidence, uint256 gasCap)
        private
        view
        returns (bool faulted, bool ok, bytes32 reason)
    {
        bytes memory data = abi.encodeWithSelector(IRecomputer.validateEvidence.selector, inputs, evidence);
        assembly ("memory-safe") {
            let success := staticcall(gasCap, recomputer, add(data, 0x20), mload(data), 0, 0)
            let good := and(success, eq(returndatasize(), 0x40))
            if good {
                returndatacopy(0, 0, 0x40)
                let b := mload(0)
                switch gt(b, 1)
                case 1 { good := 0 } // bool no canonico
                default {
                    ok := b
                    reason := mload(0x20)
                }
            }
            faulted := iszero(good)
        }
    }

    /// @dev Sin receive() ni fallback(): a este contrato no se le manda MON suelto.
    ///      La unica forma de que entre plata es commit() o challengeCommit().
}
