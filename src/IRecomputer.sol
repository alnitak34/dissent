// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRecomputer — la frontera entre el protocolo y el dominio
/// @notice DissentCore no sabe de poker, ni de trading, ni de nada. Sabe pedirle
///         un numero a esto y compararlo contra un umbral. Todo lo que sea
///         especifico de un dominio vive del otro lado de esta interfaz.
///
/// UNA SOLA FUNCION DE VALOR, NO DOS
/// El valor base es `recompute(inputs, "")`. No hay una funcion aparte para el
/// base y otra para el retado, y es a proposito:
///
///   1. Dos funciones se desincronizan. Si existieran `baseValue(inputs)` y
///      `valueWithEvidence(inputs, evidence)`, nada impediria que evolucionaran
///      distinto, y entonces comparar una contra la otra dejaria de significar
///      algo. Con una sola, que las dos ramas usen la misma aritmetica es
///      imposible de romper.
///   2. La evidencia vacia ya tiene un significado natural, y en el adaptador de
///      river mapea exactamente a lo que hace hoy _exact_river_mix cuando recibe
///      `fuente = combos`: la enumeracion completa.
///   3. El valor base tiene que ser el canonico. Si pudiera calcularse por un
///      atajo distinto, el agente elegiria el atajo que le conviene.
///
/// La validacion SI va aparte, porque es otra pregunta: en el commit no hay
/// evidencia que validar, y en el challenge puede fallar por razones de dominio
/// que el nucleo no entiende. Si viviera dentro de recompute tendria que
/// revertir, y un revert es indistinguible de quedarse sin gas.
interface IRecomputer {
    /// @notice El valor del que depende la afirmacion del agente.
    /// @param inputs   El planteo del problema, opaco para el nucleo. Va por
    ///                 calldata en cada llamada en vez de guardarse: el nucleo
    ///                 guarda solo keccak256(inputs) y lo verifica.
    /// @param evidence Vacio en el commit. Su forma la define el adaptador.
    /// @return value   En la escala que declara scale(). int256 y no uint256
    ///                 porque la interfaz tiene que servir para EV o P&L, no
    ///                 solo para probabilidades; obligar a un offset para
    ///                 representar negativos es un pie de banco.
    /// @dev `view` y no `pure` para no dejar afuera adaptadores que lean una
    ///      tabla inmutable de storage. El nucleo NO puede exigir pureza: es uno
    ///      de los limites declarados del proyecto. Que sea `view` si garantiza
    ///      que el nucleo lo invoque por STATICCALL y no pueda reentrar escribiendo.
    function recompute(bytes calldata inputs, bytes calldata evidence)
        external
        view
        returns (int256 value);

    /// @notice Si la evidencia esta bien formada para estos inputs.
    /// @return ok     false rechaza el challenge sin quedarse con el deposito.
    /// @return reason Codigo de motivo, para que el retador entienda el rechazo
    ///                sin tener que simular. Va al evento.
    function validateEvidence(bytes calldata inputs, bytes calldata evidence)
        external
        view
        returns (bool ok, bytes32 reason);

    /// @notice La escala del valor. Informativa: el nucleo compara valor contra
    ///         umbral, los dos en la misma escala por construccion.
    function scale() external pure returns (uint256);

    /// @notice Identidad del modelo y su version. El nucleo la guarda en el
    ///         compromiso y la reemite: si manana cambia la tabla del modelo, un
    ///         lector sabe que ese compromiso se resolvio con otro.
    function domain() external pure returns (bytes32);
}
