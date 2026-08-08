// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * GreenTrustChain
 *
 * Trust-driven and energy-efficient smart-contract framework for
 * sustainable blockchain-based energy markets.
 *
 * Design:
 * - On-chain layer: transaction state, trust provenance, verification policy,
 *   execution, governance state, and immutable transaction records.
 * - Off-chain layer: multidimensional trust computation and optimization.
 *
 * Trust scores and thresholds use a fixed-point scale:
 *   0     = 0.0000
 *   10000 = 1.0000
 *
 * Solidity: 0.8.24
 * OpenZeppelin Contracts: 5.x
 */
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GreenTrustChain is AccessControl, Pausable, ReentrancyGuard {
    /* -----------------------------------------------------------------
                                ROLES
    ----------------------------------------------------------------- */

    bytes32 public constant VALIDATOR_ROLE =
        keccak256("VALIDATOR_ROLE");

    bytes32 public constant GOVERNANCE_ROLE =
        keccak256("GOVERNANCE_ROLE");

    bytes32 public constant PARTICIPANT_ROLE =
        keccak256("PARTICIPANT_ROLE");

    /* -----------------------------------------------------------------
                            CONSTANTS
    ----------------------------------------------------------------- */

    uint256 public constant TRUST_SCALE = 10_000;
    uint256 public constant MAX_MODEL_VERSION_LENGTH = 64;

    /* -----------------------------------------------------------------
                                ENUMS
    ----------------------------------------------------------------- */

    enum VerificationLevel {
        Standard,   // highest trust: normal verification
        Enhanced,   // intermediate trust: additional verification
        Critical    // low trust: transaction is not committed automatically
    }

    enum TransactionStatus {
        Pending,
        Approved,
        Rejected
    }

    /* -----------------------------------------------------------------
                              STRUCTURES
    ----------------------------------------------------------------- */

    struct EnergyTransaction {
        uint256 transactionId;
        address sender;
        address validator;

        string prosumerId;

        // Dataset values are stored as scaled integers where required.
        // Scaling is defined by the experiment configuration, not inferred
        // by the contract.
        uint256 feederId;
        uint256 powerKW;
        uint256 voltagePU;
        uint256 lossIndex;
        uint256 carbonProxy;

        uint256 submittedAt;
        uint256 trustUpdatedAt;

        // Fixed-point trust score: [0, 10000] = [0.0, 1.0].
        uint256 trustScore;

        VerificationLevel verificationLevel;
        TransactionStatus status;

        // Verification provenance.
        bytes32 datasetHash;
        bytes32 modelHash;
        string modelVersion;
        uint256 inferenceTimestamp;

        // Execution and governance state.
        bool committed;
        bool feedbackApplied;
    }

    struct GovernanceParameters {
        uint256 standardThreshold;
        uint256 enhancedThreshold;
        uint256 criticalThreshold;

        uint256 governanceVersion;
        uint256 lastUpdated;
    }

    struct NetworkStatistics {
        uint256 totalTransactions;
        uint256 approvedTransactions;
        uint256 rejectedTransactions;
        uint256 pendingTransactions;

        uint256 cumulativeTrust;
        uint256 totalValidators;

        uint256 lastBlockUpdated;
    }

    /* -----------------------------------------------------------------
                              STATE
    ----------------------------------------------------------------- */

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

    // Default adaptive weights: 0.25 each on the 0-10000 scale.
    uint256 public historicalWeight = 2500;
    uint256 public consistencyWeight = 2500;
    uint256 public communicationWeight = 2500;
    uint256 public contextualWeight = 2500;

    /* -----------------------------------------------------------------
                              CUSTOM ERRORS
    ----------------------------------------------------------------- */

    error InvalidAddress();
    error AlreadyRegistered();
    error ValidatorNotRegistered();
    error ParticipantNotRegistered();
    error InvalidTransaction();
    error TransactionAlreadyProcessed();
    error InvalidTrustScore();
    error InvalidThresholds();
    error InvalidWeights();
    error EmptyProsumerId();
    error InvalidEnergyData();
    error InvalidModelVersion();
    error MissingTrustProvenance();
    error TrustAlreadyUpdated();
    error VerificationNotCompleted();
    error FeedbackAlreadyApplied();

    /* -----------------------------------------------------------------
                                EVENTS
    ----------------------------------------------------------------- */

    event ParticipantRegistered(address indexed participant);

    event ValidatorRegistered(
        address indexed validator,
        uint256 initialReputation
    );

    event TransactionSubmitted(
        uint256 indexed transactionId,
        address indexed sender,
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

    /* -----------------------------------------------------------------
                              CONSTRUCTOR
    ----------------------------------------------------------------- */

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        registeredValidators[msg.sender] = true;
        validatorReputation[msg.sender] = TRUST_SCALE;

        governance = GovernanceParameters({
            standardThreshold: 8000,
            enhancedThreshold: 6000,
            criticalThreshold: 0,
            governanceVersion: 1,
            lastUpdated: block.timestamp
        });

        statistics.totalValidators = 1;
    }

    /* -----------------------------------------------------------------
                              MODIFIERS
    ----------------------------------------------------------------- */

    modifier transactionExists(uint256 transactionId) {
        if (transactionId >= nextTransactionId) {
            revert InvalidTransaction();
        }
        _;
    }

    modifier pendingTransaction(uint256 transactionId) {
        if (
            transactions[transactionId].status
                != TransactionStatus.Pending
        ) {
            revert TransactionAlreadyProcessed();
        }
        _;
    }

    /* -----------------------------------------------------------------
                        PARTICIPANT MANAGEMENT
    ----------------------------------------------------------------- */

    /**
     * @notice Registers an energy-market participant.
     * @param participant Address representing the participant/prosumer.
     */
    function registerParticipant(address participant)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (participant == address(0)) {
            revert InvalidAddress();
        }

        if (hasRole(PARTICIPANT_ROLE, participant)) {
            revert AlreadyRegistered();
        }

        _grantRole(PARTICIPANT_ROLE, participant);

        emit ParticipantRegistered(participant);
    }

    /**
     * @notice Registers a validator and initializes its reputation.
     * @param validator Address of the validator.
     */
    function registerValidator(address validator)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (validator == address(0)) {
            revert InvalidAddress();
        }

        if (registeredValidators[validator]) {
            revert AlreadyRegistered();
        }

        registeredValidators[validator] = true;
        validatorReputation[validator] = TRUST_SCALE;

        _grantRole(VALIDATOR_ROLE, validator);

        statistics.totalValidators += 1;

        emit ValidatorRegistered(
            validator,
            TRUST_SCALE
        );
    }

    /**
     * @notice Removes a participant from the active participant role.
     */
    function revokeParticipant(address participant)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (!hasRole(PARTICIPANT_ROLE, participant)) {
            revert ParticipantNotRegistered();
        }

        _revokeRole(PARTICIPANT_ROLE, participant);
    }

    /**
     * @notice Removes a validator from the active validator set.
     */
    function revokeValidator(address validator)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (!registeredValidators[validator]) {
            revert ValidatorNotRegistered();
        }

        registeredValidators[validator] = false;
        _revokeRole(VALIDATOR_ROLE, validator);

        if (statistics.totalValidators > 0) {
            statistics.totalValidators -= 1;
        }
    }

    /* -----------------------------------------------------------------
                        TRANSACTION REGISTRATION
    ----------------------------------------------------------------- */

    /**
     * @notice Registers an energy transaction before trust evaluation.
     *
     * @dev
     * powerKW, voltagePU, lossIndex and carbonProxy are stored as
     * experiment-defined integer representations. Their scaling must be
     * documented by the associated dataset/benchmark configuration.
     */
    function submitTransaction(
        string calldata prosumerId,
        uint256 feederId,
        uint256 powerKW,
        uint256 voltagePU,
        uint256 lossIndex,
        uint256 carbonProxy
    )
        external
        whenNotPaused
        nonReentrant
        onlyRole(PARTICIPANT_ROLE)
        returns (uint256 transactionId)
    {
        if (bytes(prosumerId).length == 0) {
            revert EmptyProsumerId();
        }

        if (feederId == 0 || powerKW == 0 || voltagePU == 0) {
            revert InvalidEnergyData();
        }

        transactionId = nextTransactionId;
        nextTransactionId += 1;

        transactions[transactionId] = EnergyTransaction({
            transactionId: transactionId,
            sender: msg.sender,
            validator: address(0),
            prosumerId: prosumerId,
            feederId: feederId,
            powerKW: powerKW,
            voltagePU: voltagePU,
            lossIndex: lossIndex,
            carbonProxy: carbonProxy,
            submittedAt: block.timestamp,
            trustUpdatedAt: 0,
            trustScore: 0,
            verificationLevel: VerificationLevel.Critical,
            status: TransactionStatus.Pending,
            datasetHash: bytes32(0),
            modelHash: bytes32(0),
            modelVersion: "",
            inferenceTimestamp: 0,
            committed: false,
            feedbackApplied: false
        });

        participantTransactions[msg.sender].push(transactionId);

        statistics.totalTransactions += 1;
        statistics.pendingTransactions += 1;
        statistics.lastBlockUpdated = block.number;

        emit TransactionSubmitted(
            transactionId,
            msg.sender,
            block.timestamp
        );
    }

    /* -----------------------------------------------------------------
                          TRUST MANAGEMENT
    ----------------------------------------------------------------- */

    /**
     * @notice Stores an externally computed trust score and its provenance.
     *
     * @dev
     * Trust computation itself remains off-chain. The contract records
     * the resulting score and provenance before execution.
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
        if (trustScore > TRUST_SCALE) {
            revert InvalidTrustScore();
        }

        if (
            datasetHash == bytes32(0) ||
            modelHash == bytes32(0)
        ) {
            revert MissingTrustProvenance();
        }

        if (
            bytes(modelVersion).length == 0 ||
            bytes(modelVersion).length > MAX_MODEL_VERSION_LENGTH
        ) {
            revert InvalidModelVersion();
        }

        if (inferenceTimestamp == 0) {
            revert MissingTrustProvenance();
        }

        EnergyTransaction storage txn =
            transactions[transactionId];

        if (txn.trustUpdatedAt != 0) {
            revert TrustAlreadyUpdated();
        }

        txn.trustScore = trustScore;
        txn.trustUpdatedAt = block.timestamp;

        txn.datasetHash = datasetHash;
        txn.modelHash = modelHash;
        txn.modelVersion = modelVersion;
        txn.inferenceTimestamp = inferenceTimestamp;

        statistics.cumulativeTrust += trustScore;
        statistics.lastBlockUpdated = block.number;

        emit TrustScoreUpdated(
            transactionId,
            trustScore,
            datasetHash,
            modelHash,
            modelVersion,
            inferenceTimestamp
        );

        _assignVerificationLevel(transactionId);
    }

    /**
     * @notice Assigns verification intensity according to trust.
     */
    function _assignVerificationLevel(
        uint256 transactionId
    )
        internal
    {
        EnergyTransaction storage txn =
            transactions[transactionId];

        VerificationLevel level;

        if (
            txn.trustScore >=
            governance.standardThreshold
        ) {
            level = VerificationLevel.Standard;
        }
        else if (
            txn.trustScore >=
            governance.enhancedThreshold
        ) {
            level = VerificationLevel.Enhanced;
        }
        else {
            level = VerificationLevel.Critical;
        }

        txn.verificationLevel = level;

        emit VerificationAssigned(
            transactionId,
            level,
            txn.trustScore
        );
    }

    /* -----------------------------------------------------------------
                    TRUST-WEIGHT GOVERNANCE
    ----------------------------------------------------------------- */

    /**
     * @notice Updates the four trust-dimension weights.
     * @dev Weights use the same 0-10000 scale and must sum to 10000.
     */
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
            total != TRUST_SCALE ||
            newHistoricalWeight > TRUST_SCALE ||
            newConsistencyWeight > TRUST_SCALE ||
            newCommunicationWeight > TRUST_SCALE ||
            newContextualWeight > TRUST_SCALE
        ) {
            revert InvalidWeights();
        }

        historicalWeight = newHistoricalWeight;
        consistencyWeight = newConsistencyWeight;
        communicationWeight = newCommunicationWeight;
        contextualWeight = newContextualWeight;

        emit TrustWeightsUpdated(
            newHistoricalWeight,
            newConsistencyWeight,
            newCommunicationWeight,
            newContextualWeight,
            block.timestamp
        );
    }

    /* -----------------------------------------------------------------
                       TRANSACTION EXECUTION
    ----------------------------------------------------------------- */

    /**
     * @notice Executes the trust-aware transaction policy.
     *
     * Standard:
     *   Approved after trust validation.
     *
     * Enhanced:
     *   Approved only when the trust score remains above the enhanced
     *   threshold at execution time.
     *
     * Critical:
     *   Rejected and not committed.
     */
    function executeTransaction(uint256 transactionId)
        external
        whenNotPaused
        nonReentrant
        onlyRole(VALIDATOR_ROLE)
        transactionExists(transactionId)
        pendingTransaction(transactionId)
    {
        EnergyTransaction storage txn =
            transactions[transactionId];

        if (txn.trustUpdatedAt == 0) {
            revert VerificationNotCompleted();
        }

        txn.validator = msg.sender;

        TransactionStatus finalStatus;

        if (
            txn.verificationLevel ==
            VerificationLevel.Standard
        ) {
            finalStatus = TransactionStatus.Approved;
        }
        else if (
            txn.verificationLevel ==
            VerificationLevel.Enhanced
        ) {
            if (
                txn.trustScore >=
                governance.enhancedThreshold
            ) {
                finalStatus = TransactionStatus.Approved;
            }
            else {
                finalStatus = TransactionStatus.Rejected;
            }
        }
        else {
            finalStatus = TransactionStatus.Rejected;
        }

        txn.status = finalStatus;
        txn.committed =
            finalStatus == TransactionStatus.Approved;

        if (statistics.pendingTransactions > 0) {
            statistics.pendingTransactions -= 1;
        }

        if (finalStatus == TransactionStatus.Approved) {
            statistics.approvedTransactions += 1;
        }
        else {
            statistics.rejectedTransactions += 1;
        }

        statistics.lastBlockUpdated = block.number;

        emit TransactionExecuted(
            transactionId,
            msg.sender,
            txn.trustScore,
            txn.verificationLevel,
            finalStatus,
            block.timestamp
        );
    }

    /* -----------------------------------------------------------------
                       ADAPTIVE GOVERNANCE
    ----------------------------------------------------------------- */

    /**
     * @notice Updates execution thresholds.
     *
     * @dev
     * The ordering is:
     * standard > enhanced > critical.
     */
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
            criticalThreshold > TRUST_SCALE
        ) {
            revert InvalidThresholds();
        }

        if (
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
        governance.lastUpdated = block.timestamp;

        emit GovernanceUpdated(
            governance.governanceVersion,
            standardThreshold,
            enhancedThreshold,
            criticalThreshold,
            block.timestamp
        );
    }

    /**
     * @notice Updates a validator reputation score.
     */
    function updateValidatorReputation(
        address validator,
        uint256 reputation
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (!registeredValidators[validator]) {
            revert ValidatorNotRegistered();
        }

        if (reputation > TRUST_SCALE) {
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

    /**
     * @notice Applies execution feedback to the validator that performed it.
     *
     * @dev
     * Approved transactions increment validator reputation by one unit;
     * rejected transactions decrement it by one unit. The score remains
     * bounded by [0, TRUST_SCALE].
     */
    function governanceFeedback(uint256 transactionId)
        external
        onlyRole(GOVERNANCE_ROLE)
        transactionExists(transactionId)
    {
        EnergyTransaction storage txn =
            transactions[transactionId];

        if (txn.status == TransactionStatus.Pending) {
            revert VerificationNotCompleted();
        }

        if (txn.feedbackApplied) {
            revert FeedbackAlreadyApplied();
        }

        if (!registeredValidators[txn.validator]) {
            revert ValidatorNotRegistered();
        }

        uint256 previous =
            validatorReputation[txn.validator];

        uint256 updated = previous;

        if (
            txn.status ==
            TransactionStatus.Approved
        ) {
            if (updated < TRUST_SCALE) {
                updated += 1;
            }
        }
        else {
            if (updated > 0) {
                updated -= 1;
            }
        }

        validatorReputation[txn.validator] =
            updated;

        txn.feedbackApplied = true;

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

    /* -----------------------------------------------------------------
                         EMERGENCY CONTROLS
    ----------------------------------------------------------------- */

    /**
     * @notice Pauses new submissions and transaction execution.
     */
    function pauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _pause();
    }

    /**
     * @notice Resumes normal transaction processing.
     */
    function unpauseContract()
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _unpause();
    }

    /* -----------------------------------------------------------------
                            READ FUNCTIONS
    ----------------------------------------------------------------- */

    /**
     * @notice Returns a complete transaction record.
     */
    function getTransaction(uint256 transactionId)
        external
        view
        transactionExists(transactionId)
        returns (EnergyTransaction memory)
    {
        return transactions[transactionId];
    }

    /**
     * @notice Returns all transaction IDs submitted by a participant.
     */
    function getParticipantTransactions(address participant)
        external
        view
        returns (uint256[] memory)
    {
        return participantTransactions[participant];
    }

    /**
     * @notice Returns current governance parameters.
     */
    function getGovernanceParameters()
        external
        view
        returns (GovernanceParameters memory)
    {
        return governance;
    }

    /**
     * @notice Returns current network statistics.
     */
    function getNetworkStatistics()
        external
        view
        returns (NetworkStatistics memory)
    {
        return statistics;
    }

    /**
     * @notice Returns total transactions submitted.
     */
    function totalTransactions()
        external
        view
        returns (uint256)
    {
        return nextTransactionId;
    }

    /**
     * @notice Returns average trust using the fixed-point scale.
     */
    function averageTrust()
        external
        view
        returns (uint256)
    {
        if (statistics.totalTransactions == 0) {
            return 0;
        }

        return
            statistics.cumulativeTrust /
            statistics.totalTransactions;
    }

    /**
     * @notice Returns the current trust weights.
     */
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

    /**
     * @notice Returns whether an address is an active validator.
     */
    function isValidator(address account)
        external
        view
        returns (bool)
    {
        return registeredValidators[account];
    }

    /**
     * @notice Contract version for experiment reproducibility.
     */
    function contractVersion()
        external
        pure
        returns (string memory)
    {
        return "GreenTrustChain v1.1";
    }
}
