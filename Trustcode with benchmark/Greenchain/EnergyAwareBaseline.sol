// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EnergyAwareBaseline
 * @notice Fixed-cost, lightweight EVM execution baseline for
 *         computational-sustainability benchmarking.
 *
 * @dev
 * This contract intentionally excludes:
 *
 * - multidimensional trust evaluation
 * - adaptive trust aggregation
 * - reputation management
 * - adaptive governance
 * - dynamic verification
 * - trust-dependent execution
 *
 * The contract represents a conventional blockchain implementation
 * optimized only for a fixed lightweight execution path.
 *
 * Research purpose:
 *
 *   Determine whether GreenTrustChain provides sustainability benefits
 *   beyond a conventional lightweight smart-contract implementation.
 *
 * IMPORTANT:
 *
 * Gas usage is treated as an on-chain computational-cost indicator.
 * It is NOT reported as physical energy consumption.
 *
 * Physical energy must be measured separately at the execution-host
 * or network level.
 */
contract EnergyAwareBaseline is
    AccessControl,
    Pausable
{
    /* ===============================================================
                            ROLES
       =============================================================== */

    bytes32 public constant GOVERNANCE_ROLE =
        keccak256("GOVERNANCE_ROLE");

    bytes32 public constant PARTICIPANT_ROLE =
        keccak256("PARTICIPANT_ROLE");

    bytes32 public constant VALIDATOR_ROLE =
        keccak256("VALIDATOR_ROLE");


    /* ===============================================================
                            CONSTANTS
       =============================================================== */

    /*
     * Operational values use fixed-point representation.
     *
     * Example:
     *
     * 1000 = 1.000
     * 995  = 0.995
     */
    uint256 public constant OPERATIONAL_SCALE =
        1_000;


    /* ===============================================================
                            ENUMS
       =============================================================== */

    enum TransactionStatus {
        Pending,
        Approved,
        Rejected
    }


    /* ===============================================================
                    ENERGY TRANSACTION STRUCTURE
       =============================================================== */

    /**
     * @dev
     * Compared with the other baselines, this structure deliberately
     * stores only the fields required for lightweight execution and
     * benchmark identification.
     *
     * Trust-specific state is absent.
     */
    struct EnergyTransaction {

        uint256 transactionId;

        address sender;

        address validator;

        string prosumerId;

        string feederId;

        int256 powerKWScaled;

        uint256 voltagePUScaled;

        uint256 carbonProxyScaled;

        uint64 submittedAt;

        uint64 processedAt;

        TransactionStatus status;

        bool committed;
    }


    /* ===============================================================
                    NETWORK STATISTICS
       =============================================================== */

    struct NetworkStatistics {

        uint256 totalSubmitted;

        uint256 totalApproved;

        uint256 totalRejected;

        uint256 totalPending;

        uint256 totalCommitted;

        uint256 totalExecutionCalls;
    }


    /* ===============================================================
                            ERRORS
       =============================================================== */

    error ZeroAddress();

    error AlreadyRegistered();

    error TransactionNotFound();

    error TransactionAlreadyProcessed();


    /* ===============================================================
                        STATE VARIABLES
       =============================================================== */

    uint256 private nextTransactionId;

    mapping(uint256 => EnergyTransaction)
        private transactions;

    mapping(address => bool)
        public registeredValidators;

    mapping(address => uint256[])
        private participantTransactions;

    NetworkStatistics public statistics;


    /* ===============================================================
                            EVENTS
       =============================================================== */

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
        uint64 timestamp
    );


    /* ===============================================================
                            CONSTRUCTOR
       =============================================================== */

    constructor() {

        _grantRole(
            DEFAULT_ADMIN_ROLE,
            msg.sender
        );

        _grantRole(
            GOVERNANCE_ROLE,
            msg.sender
        );

        _grantRole(
            VALIDATOR_ROLE,
            msg.sender
        );

        registeredValidators[msg.sender] =
            true;
    }


    /* ===============================================================
                        TRANSACTION MODIFIER
       =============================================================== */

    modifier transactionExists(
        uint256 transactionId
    ) {

        if (
            transactionId >=
            nextTransactionId
        ) {
            revert TransactionNotFound();
        }

        _;
    }


    /* ===============================================================
                    PARTICIPANT REGISTRATION
       =============================================================== */

    /**
     * @notice Registers an energy-market participant.
     */
    function registerParticipant(
        address participant
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            participant == address(0)
        ) {
            revert ZeroAddress();
        }

        if (
            hasRole(
                PARTICIPANT_ROLE,
                participant
            )
        ) {
            revert AlreadyRegistered();
        }

        _grantRole(
            PARTICIPANT_ROLE,
            participant
        );

        emit ParticipantRegistered(
            participant
        );
    }


    /* ===============================================================
                    VALIDATOR REGISTRATION
       =============================================================== */

    /**
     * @notice Registers a validator.
     */
    function registerValidator(
        address validator
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            validator == address(0)
        ) {
            revert ZeroAddress();
        }

        if (
            registeredValidators[validator]
        ) {
            revert AlreadyRegistered();
        }

        registeredValidators[validator] =
            true;

        _grantRole(
            VALIDATOR_ROLE,
            validator
        );

        emit ValidatorRegistered(
            validator
        );
    }


    /* ===============================================================
                LIGHTWEIGHT TRANSACTION SUBMISSION
       =============================================================== */

    /**
     * @notice Submits an energy transaction using the lightweight
     *         execution baseline.
     *
     * @dev
     * No trust calculation or enhanced verification is performed.
     *
     * Only the minimum operational information required for the
     * benchmark is stored.
     */
    function submitTransaction(

        string calldata prosumerId,

        string calldata feederId,

        int256 powerKWScaled,

        uint256 voltagePUScaled,

        uint256 carbonProxyScaled

    )
        external
        whenNotPaused
        onlyRole(PARTICIPANT_ROLE)
        returns (
            uint256 transactionId
        )
    {

        transactionId =
            nextTransactionId++;

        transactions[
            transactionId
        ] = EnergyTransaction({

            transactionId:
                transactionId,

            sender:
                msg.sender,

            validator:
                address(0),

            prosumerId:
                prosumerId,

            feederId:
                feederId,

            powerKWScaled:
                powerKWScaled,

            voltagePUScaled:
                voltagePUScaled,

            carbonProxyScaled:
                carbonProxyScaled,

            submittedAt:
                uint64(block.timestamp),

            processedAt:
                0,

            status:
                TransactionStatus.Pending,

            committed:
                false
        });

        participantTransactions[
            msg.sender
        ].push(transactionId);

        statistics.totalSubmitted++;

        statistics.totalPending++;

        emit TransactionSubmitted(
            transactionId,
            msg.sender,
            uint64(block.timestamp)
        );
    }


    /* ===============================================================
                    LIGHTWEIGHT EXECUTION
       =============================================================== */

    /**
     * @notice Executes a transaction through a fixed lightweight
     *         validation path.
     *
     * @dev
     * Every transaction receives the same execution treatment.
     *
     * There is no:
     *
     * - trust score
     * - adaptive verification
     * - governance feedback
     * - additional verification stage
     *
     * The purpose is to provide a low-computation blockchain baseline.
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
            transactions[
                transactionId
            ];

        if (
            txn.status !=
            TransactionStatus.Pending
        ) {
            revert TransactionAlreadyProcessed();
        }

        txn.validator =
            msg.sender;

        txn.status =
            TransactionStatus.Approved;

        txn.processedAt =
            uint64(block.timestamp);

        txn.committed =
            true;

        statistics.totalPending--;

        statistics.totalApproved++;

        statistics.totalCommitted++;

        statistics.totalExecutionCalls++;

        emit TransactionExecuted(
            transactionId,
            msg.sender,
            uint64(block.timestamp)
        );
    }


    /* ===============================================================
                    BATCH EXECUTION
       =============================================================== */

    /**
     * @notice Executes multiple pending transactions in one EVM call.
     *
     * @dev
     * This function provides a controlled batching baseline.
     *
     * It reduces repeated transaction-level invocation overhead,
     * but performs no trust analysis or adaptive verification.
     *
     * The benchmark must report both:
     *
     *   1. Gas per batch
     *   2. Gas per committed transaction
     *
     * rather than comparing only total gas.
     */
    function executeBatch(
        uint256[] calldata transactionIds
    )
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
    {

        uint256 length =
            transactionIds.length;

        for (
            uint256 i = 0;
            i < length;
            ++i
        ) {

            uint256 transactionId =
                transactionIds[i];

            if (
                transactionId >=
                nextTransactionId
            ) {
                revert TransactionNotFound();
            }

            EnergyTransaction storage txn =
                transactions[
                    transactionId
                ];

            if (
                txn.status !=
                TransactionStatus.Pending
            ) {
                revert TransactionAlreadyProcessed();
            }

            txn.validator =
                msg.sender;

            txn.status =
                TransactionStatus.Approved;

            txn.processedAt =
                uint64(block.timestamp);

            txn.committed =
                true;

            statistics.totalPending--;

            statistics.totalApproved++;

            statistics.totalCommitted++;
        }

        /*
         * One external execution call represents the complete
         * batch operation.
         */
        statistics.totalExecutionCalls++;
    }


    /* ===============================================================
                        READ TRANSACTION
       =============================================================== */

    /**
     * @notice Returns a complete transaction.
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
        return transactions[
            transactionId
        ];
    }


    /* ===============================================================
                    PARTICIPANT TRANSACTION HISTORY
       =============================================================== */

    /**
     * @notice Returns all transaction IDs associated with a participant.
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


    /* ===============================================================
                        NETWORK STATISTICS
       =============================================================== */

    /**
     * @notice Returns network-level benchmark statistics.
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
     * @notice Returns total submitted transactions.
     */
    function totalTransactions()
        external
        view
        returns (
            uint256
        )
    {
        return nextTransactionId;
    }


    /**
     * @notice Returns committed transaction count.
     */
    function committedTransactions()
        external
        view
        returns (
            uint256
        )
    {
        return statistics.totalCommitted;
    }


    /* ===============================================================
                    ADMINISTRATIVE CONTROL
       =============================================================== */

    /**
     * @notice Pauses submission and execution.
     */
    function pauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _pause();
    }


    /**
     * @notice Resumes submission and execution.
     */
    function unpauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _unpause();
    }


    /* ===============================================================
                        VERSION INFORMATION
       =============================================================== */

    /**
     * @notice Returns benchmark contract version.
     */
    function contractVersion()
        external
        pure
        returns (
            string memory
        )
    {
        return
            "EnergyAwareBaseline-Ethereum-1.0";
    }
}