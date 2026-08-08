// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TrustOnlyBaseline
 * @notice Static trust-aware smart-contract baseline for GreenTrustChain.
 *
 * @dev
 * This contract isolates the effect of trust evaluation.
 *
 * It intentionally excludes:
 *
 * - adaptive trust weights
 * - adaptive governance
 * - dynamic verification-resource allocation
 * - governance feedback
 * - trust-driven policy updates
 *
 * The contract therefore provides an ablation baseline between:
 *
 *   Conventional blockchain execution
 *                 and
 *   GreenTrustChain
 *
 * Research purpose:
 *   Determine whether improvements originate from trust evaluation alone
 *   or from the complete adaptive GreenTrustChain framework.
 */
contract TrustOnlyBaseline is AccessControl, Pausable {

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

    /**
     * @dev Trust is represented as:
     *
     * 0     = minimum trust
     * 10000 = maximum trust
     *
     * Therefore:
     *
     * 7500 = 0.75
     */
    uint256 public constant TRUST_SCALE = 10_000;


    /* ===============================================================
                            ENUMS
       =============================================================== */

    enum VerificationLevel {
        Standard,
        Enhanced,
        Rejected
    }

    enum TransactionStatus {
        Pending,
        Approved,
        Rejected
    }


    /* ===============================================================
                        TRANSACTION MODEL
       =============================================================== */

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

        uint256 trustScore;

        VerificationLevel verificationLevel;

        TransactionStatus status;

        uint64 submittedAt;

        uint64 processedAt;

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

        uint256 cumulativeTrust;
    }


    /* ===============================================================
                            ERRORS
       =============================================================== */

    error ZeroAddress();

    error AlreadyRegistered();

    error TransactionNotFound();

    error TransactionAlreadyProcessed();

    error InvalidTrustScore();

    error TrustNotProvided();

    error InvalidThresholds();


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
                    FIXED TRUST POLICY
       =============================================================== */

    /**
     * @dev
     * Unlike GreenTrustChain, these thresholds remain fixed
     * throughout the experiment.
     *
     * High trust:
     *     >= 0.80
     *
     * Medium trust:
     *     >= 0.60
     *
     * Low trust:
     *     < 0.60
     */
    uint256 public constant HIGH_TRUST_THRESHOLD = 8_000;

    uint256 public constant MEDIUM_TRUST_THRESHOLD = 6_000;


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

    event TrustScoreRecorded(
        uint256 indexed transactionId,
        uint256 trustScore
    );

    event VerificationAssigned(
        uint256 indexed transactionId,
        VerificationLevel level
    );

    event TransactionExecuted(
        uint256 indexed transactionId,
        address indexed validator,
        TransactionStatus status,
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

        registeredValidators[msg.sender] = true;
    }


    /* ===============================================================
                        TRANSACTION MODIFIER
       =============================================================== */

    modifier transactionExists(
        uint256 transactionId
    ) {

        if (
            transactionId >= nextTransactionId
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

        registeredValidators[validator] = true;

        _grantRole(
            VALIDATOR_ROLE,
            validator
        );

        emit ValidatorRegistered(
            validator
        );
    }


    /* ===============================================================
                    TRANSACTION SUBMISSION
       =============================================================== */

    /**
     * @notice Submits an energy transaction.
     *
     * @dev
     * No adaptive trust calculation occurs on-chain.
     * A trust score is supplied by the external trust evaluator.
     */
    function submitTransaction(

        string calldata prosumerId,

        string calldata feederId,

        int256 powerKWScaled,

        uint256 voltagePUScaled,

        uint256 lossIndexScaled,

        uint256 curtailmentIndexScaled,

        uint256 carbonProxyScaled,

        uint256 trustScore

    )
        external
        whenNotPaused
        onlyRole(PARTICIPANT_ROLE)
        returns (
            uint256 transactionId
        )
    {

        if (
            trustScore > TRUST_SCALE
        ) {
            revert InvalidTrustScore();
        }

        transactionId =
            nextTransactionId++;

        transactions[transactionId] =
            EnergyTransaction({

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

                lossIndexScaled:
                    lossIndexScaled,

                curtailmentIndexScaled:
                    curtailmentIndexScaled,

                carbonProxyScaled:
                    carbonProxyScaled,

                trustScore:
                    trustScore,

                verificationLevel:
                    VerificationLevel.Standard,

                status:
                    TransactionStatus.Pending,

                submittedAt:
                    uint64(block.timestamp),

                processedAt:
                    0,

                committed:
                    false
            });

        participantTransactions[
            msg.sender
        ].push(transactionId);

        statistics.totalSubmitted++;

        statistics.totalPending++;

        statistics.cumulativeTrust +=
            trustScore;

        emit TransactionSubmitted(
            transactionId,
            msg.sender,
            uint64(block.timestamp)
        );

        emit TrustScoreRecorded(
            transactionId,
            trustScore
        );
    }


    /* ===============================================================
                    FIXED TRUST CLASSIFICATION
       =============================================================== */

    /**
     * @notice Assigns a fixed verification class from the
     *         supplied trust score.
     *
     * @dev
     * This is deliberately static.
     *
     * GreenTrustChain dynamically adapts the verification policy,
     * whereas this baseline applies the same thresholds to every
     * transaction.
     */
    function assignVerificationLevel(
        uint256 transactionId
    )
        public
        transactionExists(transactionId)
    {

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.trustScore == 0
        ) {
            revert TrustNotProvided();
        }

        if (
            txn.trustScore >=
            HIGH_TRUST_THRESHOLD
        ) {

            txn.verificationLevel =
                VerificationLevel.Standard;

        } else if (
            txn.trustScore >=
            MEDIUM_TRUST_THRESHOLD
        ) {

            txn.verificationLevel =
                VerificationLevel.Enhanced;

        } else {

            txn.verificationLevel =
                VerificationLevel.Rejected;
        }

        emit VerificationAssigned(
            transactionId,
            txn.verificationLevel
        );
    }


    /* ===============================================================
                    FIXED TRUST EXECUTION
       =============================================================== */

    /**
     * @notice Executes a transaction using the fixed trust policy.
     *
     * @dev
     * The baseline has three deterministic outcomes:
     *
     * High trust:
     *     Standard execution.
     *
     * Medium trust:
     *     Enhanced verification.
     *
     * Low trust:
     *     Rejection.
     *
     * There is no adaptive governance or resource allocation.
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
            txn.status !=
            TransactionStatus.Pending
        ) {
            revert TransactionAlreadyProcessed();
        }

        assignVerificationLevel(
            transactionId
        );

        txn.validator =
            msg.sender;

        txn.processedAt =
            uint64(block.timestamp);

        if (
            txn.verificationLevel ==
            VerificationLevel.Rejected
        ) {

            txn.status =
                TransactionStatus.Rejected;

            statistics.totalRejected++;

        } else {

            txn.status =
                TransactionStatus.Approved;

            txn.committed = true;

            statistics.totalApproved++;
        }

        statistics.totalPending--;

        emit TransactionExecuted(
            transactionId,
            msg.sender,
            txn.status,
            uint64(block.timestamp)
        );
    }


    /* ===============================================================
                        READ TRANSACTION
       =============================================================== */

    /**
     * @notice Returns a complete transaction record.
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
                    PARTICIPANT HISTORY
       =============================================================== */

    /**
     * @notice Returns transaction IDs associated with a participant.
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
     * @notice Returns benchmark statistics.
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
     * @notice Returns the number of submitted transactions.
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
     * @notice Returns the mean trust score.
     *
     * @dev
     * Result remains scaled by TRUST_SCALE.
     */
    function averageTrust()
        external
        view
        returns (
            uint256
        )
    {

        if (
            statistics.totalSubmitted == 0
        ) {
            return 0;
        }

        return
            statistics.cumulativeTrust /
            statistics.totalSubmitted;
    }


    /* ===============================================================
                    ADMINISTRATIVE CONTROL
       =============================================================== */

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
            "TrustOnlyBaseline-Ethereum-1.0";
    }
}