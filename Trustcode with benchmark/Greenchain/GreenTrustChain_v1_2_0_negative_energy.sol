// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GreenTrustChain
 * @version 1.2.0
 *
 * @notice Trust-aware and energy-aware smart-contract benchmark contract.
 *
 * ENERGY-FLOW CONSTRAINT
 * ----------------------
 * powerKWScaled is intentionally signed:
 *
 *   powerKWScaled > 0  = net import / local demand
 *   powerKWScaled == 0 = balanced flow
 *   powerKWScaled < 0  = net export / local surplus
 *
 * A negative value is VALID and MUST NOT be rejected merely because it is
 * negative. It represents energy exported from the local prosumer/system
 * toward the nearby grid or an adjacent energy source.
 *
 * This preserves bidirectional energy-flow observations in the benchmark.
 */
contract GreenTrustChain is
    AccessControl,
    Pausable,
    ReentrancyGuard
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

    uint256 public constant TRUST_SCALE = 10_000;

    uint256 public constant DEFAULT_STANDARD_THRESHOLD = 8_000;
    uint256 public constant DEFAULT_ENHANCED_THRESHOLD = 6_000;
    uint256 public constant DEFAULT_CRITICAL_THRESHOLD = 0;

    uint256 public constant WEIGHT_SCALE = 10_000;

    uint256 public constant MAX_MODEL_VERSION_LENGTH = 64;


    /* ===============================================================
                              ENUMS
       =============================================================== */

    enum VerificationLevel {
        Standard,
        Enhanced,
        Critical
    }

    enum TransactionStatus {
        Pending,
        Approved,
        Rejected
    }

    /**
     * @dev Direction of net energy flow.
     */
    enum PowerFlow {
        Balanced,
        Import,
        Export
    }


    /* ===============================================================
                       ENERGY TRANSACTION MODEL
       =============================================================== */

    struct EnergyTransaction {

        uint256 transactionId;

        address sender;

        address validator;

        string prosumerId;

        string feederId;

        /**
         * @dev Signed fixed-point power value.
         *
         * Positive = import / demand
         * Negative = export / surplus
         */
        int256 powerKWScaled;

        uint256 voltagePUScaled;

        uint256 lossIndexScaled;

        uint256 curtailmentIndexScaled;

        uint256 carbonProxyScaled;

        uint256 trustScore;

        VerificationLevel verificationLevel;

        TransactionStatus status;

        uint256 submittedAt;

        uint256 processedAt;

        uint256 trustUpdatedAt;

        bytes32 datasetHash;

        bytes32 modelHash;

        string modelVersion;

        uint256 inferenceTimestamp;

        bool committed;

        bool feedbackApplied;
    }


    /* ===============================================================
                       GOVERNANCE MODEL
       =============================================================== */

    struct GovernanceParameters {

        uint256 standardThreshold;

        uint256 enhancedThreshold;

        uint256 criticalThreshold;

        uint256 governanceVersion;

        uint256 lastUpdated;
    }


    /* ===============================================================
                       NETWORK STATISTICS
       =============================================================== */

    struct NetworkStatistics {

        uint256 totalTransactions;

        uint256 approvedTransactions;

        uint256 rejectedTransactions;

        uint256 pendingTransactions;

        uint256 cumulativeTrust;

        uint256 totalValidators;

        uint256 totalExports;

        uint256 totalImports;

        uint256 totalBalanced;

        uint256 lastBlockUpdated;
    }


    /* ===============================================================
                         TRUST WEIGHTS
       =============================================================== */

    uint256 public historicalWeight = 2_500;

    uint256 public consistencyWeight = 2_500;

    uint256 public communicationWeight = 2_500;

    uint256 public contextualWeight = 2_500;


    /* ===============================================================
                         STATE VARIABLES
       =============================================================== */

    uint256 private nextTransactionId;

    mapping(uint256 => EnergyTransaction)
        private transactions;

    mapping(address => bool)
        public registeredValidators;

    mapping(address => uint256)
        public validatorReputation;

    mapping(address => uint256[])
        private participantTransactions;

    GovernanceParameters public governance;

    NetworkStatistics public statistics;


    /* ===============================================================
                              ERRORS
       =============================================================== */

    error InvalidAddress();

    error AlreadyRegistered();

    error ValidatorNotRegistered();

    error ParticipantNotRegistered();

    error TransactionNotFound();

    error TransactionAlreadyProcessed();

    error InvalidTrustScore();

    error InvalidThresholds();

    error InvalidWeights();

    error EmptyIdentifier();

    error InvalidEnergyData();

    error InvalidModelVersion();

    error MissingTrustProvenance();

    error TrustAlreadyUpdated();

    error VerificationNotCompleted();

    error FeedbackAlreadyApplied();


    /* ===============================================================
                              EVENTS
       =============================================================== */

    event ParticipantRegistered(
        address indexed participant
    );

    event ValidatorRegistered(
        address indexed validator,
        uint256 initialReputation
    );

    event ParticipantRevoked(
        address indexed participant
    );

    event ValidatorRevoked(
        address indexed validator
    );

    event TransactionSubmitted(
        uint256 indexed transactionId,
        address indexed sender,
        int256 powerKWScaled,
        PowerFlow powerFlow,
        uint256 timestamp
    );

    event TrustScoreUpdated(
        uint256 indexed transactionId,
        uint256 trustScore,
        bytes32 indexed datasetHash,
        bytes32 indexed modelHash,
        string modelVersion,
        uint256 inferenceTimestamp
    );

    event VerificationAssigned(
        uint256 indexed transactionId,
        VerificationLevel level,
        uint256 trustScore
    );

    event TransactionExecuted(
        uint256 indexed transactionId,
        address indexed validator,
        uint256 trustScore,
        VerificationLevel level,
        TransactionStatus status,
        uint256 timestamp
    );

    event GovernanceUpdated(
        uint256 indexed version,
        uint256 standardThreshold,
        uint256 enhancedThreshold,
        uint256 criticalThreshold,
        uint256 timestamp
    );

    event TrustWeightsUpdated(
        uint256 historicalWeight,
        uint256 consistencyWeight,
        uint256 communicationWeight,
        uint256 contextualWeight,
        uint256 timestamp
    );

    event ValidatorReputationUpdated(
        address indexed validator,
        uint256 previousReputation,
        uint256 newReputation
    );

    event GovernanceFeedbackApplied(
        uint256 indexed transactionId,
        address indexed validator,
        uint256 newReputation
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

        validatorReputation[msg.sender] =
            TRUST_SCALE;

        governance = GovernanceParameters({
            standardThreshold:
                DEFAULT_STANDARD_THRESHOLD,

            enhancedThreshold:
                DEFAULT_ENHANCED_THRESHOLD,

            criticalThreshold:
                DEFAULT_CRITICAL_THRESHOLD,

            governanceVersion:
                1,

            lastUpdated:
                block.timestamp
        });

        statistics.totalValidators = 1;
    }


    /* ===============================================================
                            MODIFIERS
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

    modifier pendingTransaction(
        uint256 transactionId
    ) {

        if (
            transactions[transactionId].status !=
            TransactionStatus.Pending
        ) {
            revert TransactionAlreadyProcessed();
        }

        _;
    }


    /* ===============================================================
                      PARTICIPANT MANAGEMENT
       =============================================================== */

    function registerParticipant(
        address participant
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            participant == address(0)
        ) {
            revert InvalidAddress();
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


    function revokeParticipant(
        address participant
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            !hasRole(
                PARTICIPANT_ROLE,
                participant
            )
        ) {
            revert ParticipantNotRegistered();
        }

        _revokeRole(
            PARTICIPANT_ROLE,
            participant
        );

        emit ParticipantRevoked(
            participant
        );
    }


    /* ===============================================================
                       VALIDATOR MANAGEMENT
       =============================================================== */

    function registerValidator(
        address validator
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            validator == address(0)
        ) {
            revert InvalidAddress();
        }

        if (
            registeredValidators[validator]
        ) {
            revert AlreadyRegistered();
        }

        registeredValidators[validator] = true;

        validatorReputation[validator] =
            TRUST_SCALE;

        _grantRole(
            VALIDATOR_ROLE,
            validator
        );

        statistics.totalValidators += 1;

        emit ValidatorRegistered(
            validator,
            TRUST_SCALE
        );
    }


    function revokeValidator(
        address validator
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            !registeredValidators[validator]
        ) {
            revert ValidatorNotRegistered();
        }

        registeredValidators[validator] = false;

        _revokeRole(
            VALIDATOR_ROLE,
            validator
        );

        if (
            statistics.totalValidators > 0
        ) {
            statistics.totalValidators -= 1;
        }

        emit ValidatorRevoked(
            validator
        );
    }


    /* ===============================================================
                    ENERGY TRANSACTION SUBMISSION
       =============================================================== */

    /**
     * @notice Submit an energy transaction.
     *
     * @dev
     * Negative power is explicitly permitted.
     *
     * Example:
     *
     *   +150000 = +150 kW import
     *   0       = balanced
     *   -150000 = -150 kW export
     *
     * The benchmark replay currently scales power by 1,000.
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
        nonReentrant
        onlyRole(PARTICIPANT_ROLE)
        returns (
            uint256 transactionId
        )
    {

        if (
            bytes(prosumerId).length == 0 ||
            bytes(feederId).length == 0
        ) {
            revert EmptyIdentifier();
        }

        if (
            voltagePUScaled == 0
        ) {
            revert InvalidEnergyData();
        }

        transactionId =
            nextTransactionId++;

        PowerFlow flow =
            _classifyPowerFlow(
                powerKWScaled
            );

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
                    0,

                verificationLevel:
                    VerificationLevel.Critical,

                status:
                    TransactionStatus.Pending,

                submittedAt:
                    block.timestamp,

                processedAt:
                    0,

                trustUpdatedAt:
                    0,

                datasetHash:
                    bytes32(0),

                modelHash:
                    bytes32(0),

                modelVersion:
                    "",

                inferenceTimestamp:
                    0,

                committed:
                    false,

                feedbackApplied:
                    false
            });

        participantTransactions[
            msg.sender
        ].push(transactionId);

        statistics.totalTransactions += 1;

        statistics.pendingTransactions += 1;

        statistics.lastBlockUpdated =
            block.number;

        if (
            flow == PowerFlow.Export
        ) {

            statistics.totalExports += 1;

        } else if (
            flow == PowerFlow.Import
        ) {

            statistics.totalImports += 1;

        } else {

            statistics.totalBalanced += 1;
        }

        emit TransactionSubmitted(
            transactionId,
            msg.sender,
            powerKWScaled,
            flow,
            block.timestamp
        );
    }


    /* ===============================================================
                         TRUST UPDATE
       =============================================================== */

    /**
     * @notice Records externally evaluated trust with reproducibility
     *         provenance.
     *
     * @dev
     * datasetHash and modelHash allow the benchmark result to identify
     * the exact dataset/model configuration used for inference.
     */
    function updateTrustScore(
        uint256 transactionId,
        uint256 trustScore,
        bytes32 datasetHash,
        bytes32 modelHash,
        string calldata modelVersion,
        uint256 inferenceTimestamp
    )
        external
        onlyRole(VALIDATOR_ROLE)
        transactionExists(transactionId)
        pendingTransaction(transactionId)
    {

        if (
            trustScore > TRUST_SCALE
        ) {
            revert InvalidTrustScore();
        }

        if (
            datasetHash == bytes32(0) ||
            modelHash == bytes32(0) ||
            inferenceTimestamp == 0
        ) {
            revert MissingTrustProvenance();
        }

        if (
            bytes(modelVersion).length == 0 ||
            bytes(modelVersion).length >
            MAX_MODEL_VERSION_LENGTH
        ) {
            revert InvalidModelVersion();
        }

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.trustUpdatedAt != 0
        ) {
            revert TrustAlreadyUpdated();
        }

        txn.trustScore =
            trustScore;

        txn.trustUpdatedAt =
            block.timestamp;

        txn.datasetHash =
            datasetHash;

        txn.modelHash =
            modelHash;

        txn.modelVersion =
            modelVersion;

        txn.inferenceTimestamp =
            inferenceTimestamp;

        statistics.cumulativeTrust +=
            trustScore;

        statistics.lastBlockUpdated =
            block.number;

        emit TrustScoreUpdated(
            transactionId,
            trustScore,
            datasetHash,
            modelHash,
            modelVersion,
            inferenceTimestamp
        );

        _assignVerificationLevel(
            transactionId
        );
    }


    /* ===============================================================
                    ADAPTIVE VERIFICATION POLICY
       =============================================================== */

    function _assignVerificationLevel(
        uint256 transactionId
    )
        internal
    {

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.trustScore >=
            governance.standardThreshold
        ) {

            txn.verificationLevel =
                VerificationLevel.Standard;

        } else if (
            txn.trustScore >=
            governance.enhancedThreshold
        ) {

            txn.verificationLevel =
                VerificationLevel.Enhanced;

        } else {

            txn.verificationLevel =
                VerificationLevel.Critical;
        }

        emit VerificationAssigned(
            transactionId,
            txn.verificationLevel,
            txn.trustScore
        );
    }


    /* ===============================================================
                         TRANSACTION EXECUTION
       =============================================================== */

    function executeTransaction(
        uint256 transactionId
    )
        external
        whenNotPaused
        nonReentrant
        onlyRole(VALIDATOR_ROLE)
        transactionExists(transactionId)
        pendingTransaction(transactionId)
    {

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.trustUpdatedAt == 0
        ) {
            revert VerificationNotCompleted();
        }

        txn.validator =
            msg.sender;

        txn.processedAt =
            block.timestamp;

        TransactionStatus finalStatus;

        if (
            txn.verificationLevel ==
            VerificationLevel.Standard
        ) {

            finalStatus =
                TransactionStatus.Approved;

        } else if (
            txn.verificationLevel ==
            VerificationLevel.Enhanced
        ) {

            finalStatus =
                txn.trustScore >=
                governance.enhancedThreshold
                    ? TransactionStatus.Approved
                    : TransactionStatus.Rejected;

        } else {

            finalStatus =
                TransactionStatus.Rejected;
        }

        txn.status =
            finalStatus;

        txn.committed =
            finalStatus ==
            TransactionStatus.Approved;

        if (
            statistics.pendingTransactions > 0
        ) {
            statistics.pendingTransactions -= 1;
        }

        if (
            finalStatus ==
            TransactionStatus.Approved
        ) {

            statistics.approvedTransactions += 1;

        } else {

            statistics.rejectedTransactions += 1;
        }

        statistics.lastBlockUpdated =
            block.number;

        emit TransactionExecuted(
            transactionId,
            msg.sender,
            txn.trustScore,
            txn.verificationLevel,
            finalStatus,
            block.timestamp
        );
    }


    /* ===============================================================
                       GOVERNANCE: TRUST WEIGHTS
       =============================================================== */

    function updateTrustWeights(
        uint256 newHistoricalWeight,
        uint256 newConsistencyWeight,
        uint256 newCommunicationWeight,
        uint256 newContextualWeight
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        uint256 total =
            newHistoricalWeight +
            newConsistencyWeight +
            newCommunicationWeight +
            newContextualWeight;

        if (
            total != WEIGHT_SCALE ||
            newHistoricalWeight > WEIGHT_SCALE ||
            newConsistencyWeight > WEIGHT_SCALE ||
            newCommunicationWeight > WEIGHT_SCALE ||
            newContextualWeight > WEIGHT_SCALE
        ) {
            revert InvalidWeights();
        }

        historicalWeight =
            newHistoricalWeight;

        consistencyWeight =
            newConsistencyWeight;

        communicationWeight =
            newCommunicationWeight;

        contextualWeight =
            newContextualWeight;

        emit TrustWeightsUpdated(
            newHistoricalWeight,
            newConsistencyWeight,
            newCommunicationWeight,
            newContextualWeight,
            block.timestamp
        );
    }


    /* ===============================================================
                    GOVERNANCE: THRESHOLDS
       =============================================================== */

    function updateGovernanceParameters(
        uint256 standardThreshold,
        uint256 enhancedThreshold,
        uint256 criticalThreshold
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            standardThreshold > TRUST_SCALE ||
            enhancedThreshold > TRUST_SCALE ||
            criticalThreshold > TRUST_SCALE ||
            standardThreshold <= enhancedThreshold ||
            enhancedThreshold < criticalThreshold
        ) {
            revert InvalidThresholds();
        }

        governance.standardThreshold =
            standardThreshold;

        governance.enhancedThreshold =
            enhancedThreshold;

        governance.criticalThreshold =
            criticalThreshold;

        governance.governanceVersion += 1;

        governance.lastUpdated =
            block.timestamp;

        emit GovernanceUpdated(
            governance.governanceVersion,
            standardThreshold,
            enhancedThreshold,
            criticalThreshold,
            block.timestamp
        );
    }


    /* ===============================================================
                    GOVERNANCE: VALIDATOR REPUTATION
       =============================================================== */

    function updateValidatorReputation(
        address validator,
        uint256 reputation
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {

        if (
            !registeredValidators[validator]
        ) {
            revert ValidatorNotRegistered();
        }

        if (
            reputation > TRUST_SCALE
        ) {
            revert InvalidTrustScore();
        }

        uint256 previous =
            validatorReputation[validator];

        validatorReputation[validator] =
            reputation;

        emit ValidatorReputationUpdated(
            validator,
            previous,
            reputation
        );
    }


    /* ===============================================================
                    GOVERNANCE FEEDBACK
       =============================================================== */

    function governanceFeedback(
        uint256 transactionId
    )
        external
        onlyRole(GOVERNANCE_ROLE)
        transactionExists(transactionId)
    {

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (
            txn.status ==
            TransactionStatus.Pending
        ) {
            revert VerificationNotCompleted();
        }

        if (
            txn.feedbackApplied
        ) {
            revert FeedbackAlreadyApplied();
        }

        if (
            !registeredValidators[txn.validator]
        ) {
            revert ValidatorNotRegistered();
        }

        uint256 previous =
            validatorReputation[
                txn.validator
            ];

        uint256 updated =
            previous;

        if (
            txn.status ==
            TransactionStatus.Approved
        ) {

            if (
                updated < TRUST_SCALE
            ) {
                updated += 1;
            }

        } else {

            if (
                updated > 0
            ) {
                updated -= 1;
            }
        }

        validatorReputation[
            txn.validator
        ] = updated;

        txn.feedbackApplied =
            true;

        emit ValidatorReputationUpdated(
            txn.validator,
            previous,
            updated
        );

        emit GovernanceFeedbackApplied(
            transactionId,
            txn.validator,
            updated
        );
    }


    /* ===============================================================
                         PAUSE CONTROL
       =============================================================== */

    function pauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _pause();
    }


    function unpauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _unpause();
    }


    /* ===============================================================
                       ENERGY-FLOW HELPERS
       =============================================================== */

    function _classifyPowerFlow(
        int256 powerKWScaled
    )
        internal
        pure
        returns (PowerFlow)
    {

        if (
            powerKWScaled < 0
        ) {

            return PowerFlow.Export;

        } else if (
            powerKWScaled > 0
        ) {

            return PowerFlow.Import;

        } else {

            return PowerFlow.Balanced;
        }
    }


    function getPowerFlow(
        uint256 transactionId
    )
        external
        view
        transactionExists(transactionId)
        returns (PowerFlow)
    {

        return _classifyPowerFlow(
            transactions[
                transactionId
            ].powerKWScaled
        );
    }


    function isExportTransaction(
        uint256 transactionId
    )
        external
        view
        transactionExists(transactionId)
        returns (bool)
    {

        return
            transactions[
                transactionId
            ].powerKWScaled < 0;
    }


    function isImportTransaction(
        uint256 transactionId
    )
        external
        view
        transactionExists(transactionId)
        returns (bool)
    {

        return
            transactions[
                transactionId
            ].powerKWScaled > 0;
    }


    function getSignedPower(
        uint256 transactionId
    )
        external
        view
        transactionExists(transactionId)
        returns (int256)
    {

        return
            transactions[
                transactionId
            ].powerKWScaled;
    }


    /* ===============================================================
                            READ FUNCTIONS
       =============================================================== */

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

        return
            transactions[
                transactionId
            ];
    }


    function getParticipantTransactions(
        address participant
    )
        external
        view
        returns (
            uint256[] memory
        )
    {

        return
            participantTransactions[
                participant
            ];
    }


    function getGovernanceParameters()
        external
        view
        returns (
            GovernanceParameters memory
        )
    {

        return governance;
    }


    function getNetworkStatistics()
        external
        view
        returns (
            NetworkStatistics memory
        )
    {

        return statistics;
    }


    function getTrustWeights()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {

        return (
            historicalWeight,
            consistencyWeight,
            communicationWeight,
            contextualWeight
        );
    }


    function totalTransactions()
        external
        view
        returns (uint256)
    {

        return nextTransactionId;
    }


    function averageTrust()
        external
        view
        returns (uint256)
    {

        if (
            statistics.totalTransactions == 0
        ) {
            return 0;
        }

        return
            statistics.cumulativeTrust /
            statistics.totalTransactions;
    }


    function isValidator(
        address account
    )
        external
        view
        returns (bool)
    {

        return registeredValidators[
            account
        ];
    }


    /* ===============================================================
                          VERSION / METADATA
       =============================================================== */

    function contractVersion()
        external
        pure
        returns (string memory)
    {

        return
            "GreenTrustChain-v1.2.0-negative-energy";
    }
}
