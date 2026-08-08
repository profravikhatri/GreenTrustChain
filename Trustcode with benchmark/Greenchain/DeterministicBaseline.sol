// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title DeterministicBaseline
 * @notice Conventional fixed-policy EVM smart-contract baseline for
 *         benchmarking against GreenTrustChain.
 *
 * @dev
 * This contract intentionally does NOT implement:
 *   - multidimensional trust evaluation
 *   - adaptive trust weights
 *   - trust thresholds
 *   - enhanced verification
 *   - trust-driven computational allocation
 *   - governance feedback
 *
 * Every accepted transaction follows the same deterministic validation path.
 *
 * Research purpose:
 *   This contract provides the conventional baseline against which
 *   GreenTrustChain can be compared in terms of:
 *
 *   - gas consumption
 *   - execution latency
 *   - throughput
 *   - transaction success rate
 *   - storage overhead
 *   - contract execution overhead
 *
 * Important:
 *   Gas consumption is NOT interpreted as physical energy consumption.
 *   Physical energy measurements must be obtained separately from the
 *   execution environment.
 */
contract DeterministicBaseline is AccessControl, Pausable {
    bytes32 public constant GOVERNANCE_ROLE =
        keccak256("GOVERNANCE_ROLE");

    bytes32 public constant PARTICIPANT_ROLE =
        keccak256("PARTICIPANT_ROLE");

    bytes32 public constant VALIDATOR_ROLE =
        keccak256("VALIDATOR_ROLE");

    uint256 public constant POWER_SCALE = 1_000;
    uint256 public constant OPERATIONAL_SCALE = 1_000_000;

    enum TransactionStatus {
        Pending,
        Approved,
        Rejected
    }

    /**
     * @dev Energy transaction deliberately mirrors the principal
     *      transaction payload used by GreenTrustChain.
     *
     *      Trust-specific fields are intentionally absent.
     */
    struct EnergyTransaction {
        uint256 transactionId;

        address sender;
        address validator;

        string prosumerId;
        string feederId;

        int256 powerKWScaled;

        uint256 voltagePUScaled;
        uint256 lossIndexScaled;
        uint256 curtailmentIndexScaled;
        uint256 carbonProxyScaled;

        uint64 submittedAt;
        uint64 processedAt;

        TransactionStatus status;

        bool committed;
    }

    struct NetworkStatistics {
        uint256 totalSubmitted;
        uint256 totalApproved;
        uint256 totalRejected;
        uint256 totalPending;
    }

    error ZeroAddress();
    error AlreadyRegistered();
    error TransactionNotFound();
    error TransactionAlreadyProcessed();
    error InvalidTransactionState();

    uint256 private nextTransactionId;

    mapping(uint256 => EnergyTransaction)
        private transactions;

    mapping(address => bool)
        public registeredValidators;

    mapping(address => uint256[])
        private participantTransactions;

    NetworkStatistics public statistics;

    event ParticipantRegistered(
        address indexed participant
    );

    event ValidatorRegistered(
        address indexed validator
    );

    event TransactionSubmitted(
        uint256 indexed transactionId,
        address indexed sender,
        uint64 timestamp
    );

    event TransactionExecuted(
        uint256 indexed transactionId,
        address indexed validator,
        TransactionStatus status,
        uint64 timestamp
    );

    /**
     * @dev Constructor establishes the deployer as administrator,
     *      participant and validator.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        registeredValidators[msg.sender] = true;
    }

    /**
     * @dev Ensures the transaction exists.
     */
    modifier transactionExists(uint256 transactionId) {
        if (transactionId >= nextTransactionId) {
            revert TransactionNotFound();
        }

        _;
    }

    /**
     * @notice Registers an energy-market participant.
     */
    function registerParticipant(
        address participant
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (participant == address(0)) {
            revert ZeroAddress();
        }

        if (hasRole(PARTICIPANT_ROLE, participant)) {
            revert AlreadyRegistered();
        }

        _grantRole(PARTICIPANT_ROLE, participant);

        emit ParticipantRegistered(participant);
    }

    /**
     * @notice Registers a validator.
     */
    function registerValidator(
        address validator
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (validator == address(0)) {
            revert ZeroAddress();
        }

        if (registeredValidators[validator]) {
            revert AlreadyRegistered();
        }

        registeredValidators[validator] = true;

        _grantRole(
            VALIDATOR_ROLE,
            validator
        );

        emit ValidatorRegistered(validator);
    }

    /**
     * @notice Creates an energy transaction.
     *
     * @dev
     * No trust evaluation occurs here.
     *
     * This is deliberately equivalent to conventional blockchain
     * transaction acceptance: authenticated participant submits
     * operational data and the transaction enters the pending pool.
     */
    function submitTransaction(
        string calldata prosumerId,
        string calldata feederId,
        int256 powerKWScaled,
        uint256 voltagePUScaled,
        uint256 lossIndexScaled,
        uint256 curtailmentIndexScaled,
        uint256 carbonProxyScaled
    )
        external
        whenNotPaused
        onlyRole(PARTICIPANT_ROLE)
        returns (uint256 transactionId)
    {
        transactionId = nextTransactionId++;

        transactions[transactionId] = EnergyTransaction({
            transactionId: transactionId,
            sender: msg.sender,
            validator: address(0),

            prosumerId: prosumerId,
            feederId: feederId,

            powerKWScaled: powerKWScaled,

            voltagePUScaled: voltagePUScaled,
            lossIndexScaled: lossIndexScaled,
            curtailmentIndexScaled: curtailmentIndexScaled,
            carbonProxyScaled: carbonProxyScaled,

            submittedAt: uint64(block.timestamp),
            processedAt: 0,

            status: TransactionStatus.Pending,

            committed: false
        });

        participantTransactions[msg.sender]
            .push(transactionId);

        statistics.totalSubmitted++;
        statistics.totalPending++;

        emit TransactionSubmitted(
            transactionId,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Executes a submitted transaction using a fixed
     *         deterministic validation policy.
     *
     * @dev
     * Every transaction follows exactly the same execution path.
     *
     * There is intentionally no:
     *
     *   - trust score
     *   - adaptive verification
     *   - model inference
     *   - trust threshold
     *   - additional verification stage
     *
     * This represents the conventional baseline.
     */
    function executeTransaction(
        uint256 transactionId
    )
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
        transactionExists(transactionId)
    {
        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.status != TransactionStatus.Pending
        ) {
            revert TransactionAlreadyProcessed();
        }

        /*
         * Conventional deterministic policy:
         *
         * Authentication and basic transaction validity are
         * sufficient for execution.
         *
         * The baseline does not attempt to determine whether
         * the operational measurement is trustworthy.
         */
        txn.validator = msg.sender;

        txn.status =
            TransactionStatus.Approved;

        txn.processedAt =
            uint64(block.timestamp);

        txn.committed = true;

        statistics.totalPending--;
        statistics.totalApproved++;

        emit TransactionExecuted(
            transactionId,
            msg.sender,
            TransactionStatus.Approved,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Returns a stored transaction.
     */
    function getTransaction(
        uint256 transactionId
    )
        external
        view
        transactionExists(transactionId)
        returns (
            EnergyTransaction memory
        )
    {
        return transactions[transactionId];
    }

    /**
     * @notice Returns all transaction IDs submitted
     *         by a participant.
     */
    function getParticipantTransactions(
        address participant
    )
        external
        view
        returns (
            uint256[] memory
        )
    {
        return participantTransactions[
            participant
        ];
    }

    /**
     * @notice Returns network statistics.
     */
    function getNetworkStatistics()
        external
        view
        returns (
            NetworkStatistics memory
        )
    {
        return statistics;
    }

    /**
     * @notice Returns the total number of submitted transactions.
     */
    function totalTransactions()
        external
        view
        returns (uint256)
    {
        return nextTransactionId;
    }

    /**
     * @notice Returns the number of successfully committed
     *         transactions.
     */
    function successfulTransactions()
        external
        view
        returns (uint256)
    {
        return statistics.totalApproved;
    }

    /**
     * @notice Pauses transaction submission and execution.
     */
    function pauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _pause();
    }

    /**
     * @notice Resumes transaction submission and execution.
     */
    function unpauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _unpause();
    }

    /**
     * @notice Returns the benchmark contract version.
     */
    function contractVersion()
        external
        pure
        returns (string memory)
    {
        return "DeterministicBaseline-Ethereum-1.0";
    }
}