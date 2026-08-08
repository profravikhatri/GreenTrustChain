// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IGreenTrustChain
 * @notice Public interface for the GreenTrustChain research framework.
 *
 * @dev
 * This interface defines the externally observable behaviour of
 * GreenTrustChain without exposing implementation details.
 *
 * The interface is intended to support:
 *
 * 1. Smart-contract integration
 * 2. Benchmark automation
 * 3. Event-based experiment logging
 * 4. Reproducible blockchain experiments
 * 5. Future alternative implementations
 */
interface IGreenTrustChain {

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


    /* ===============================================================
                        TRANSACTION STRUCTURE
       =============================================================== */

    struct EnergyTransaction {

        uint256 transactionId;

        address sender;

        address validator;

        string prosumerId;

        string feederId;

        uint256 feederIdNumeric;

        uint256 powerKW;

        uint256 voltagePU;

        uint256 lossIndex;

        uint256 curtailmentIndex;

        uint256 carbonProxy;

        uint256 trustScore;

        bytes32 datasetHash;

        bytes32 modelHash;

        string modelVersion;

        uint256 inferenceTimestamp;

        VerificationLevel verificationLevel;

        TransactionStatus status;

        uint256 submittedAt;

        uint256 processedAt;

        bool trustEvaluated;

        bool committed;
    }


    /* ===============================================================
                        GOVERNANCE STRUCTURE
       =============================================================== */

    struct GovernanceParameters {

        uint256 standardThreshold;

        uint256 enhancedThreshold;

        uint256 criticalThreshold;

        uint256 governanceVersion;

        uint256 lastUpdated;

        uint256 learningRate;
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

        uint256 totalTrustEvaluations;

        uint256 totalEnhancedVerifications;

        uint256 lastBlockUpdated;
    }


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
        uint256 timestamp
    );

    event TrustScoreUpdated(
        uint256 indexed transactionId,
        uint256 trustScore,
        bytes32 indexed datasetHash,
        bytes32 indexed modelHash
    );

    event VerificationAssigned(
        uint256 indexed transactionId,
        VerificationLevel level,
        uint256 trustScore
    );

    event TransactionExecuted(
        uint256 indexed transactionId,
        address indexed validator,
        TransactionStatus status,
        uint256 trustScore,
        VerificationLevel level,
        uint256 timestamp
    );

    event GovernanceUpdated(
        uint256 indexed version,
        uint256 standardThreshold,
        uint256 enhancedThreshold,
        uint256 criticalThreshold,
        uint256 timestamp
    );

    event ValidatorReputationUpdated(
        address indexed validator,
        uint256 previousReputation,
        uint256 newReputation
    );


    /* ===============================================================
                    PARTICIPANT MANAGEMENT
       =============================================================== */

    function registerParticipant(
        address participant
    )
        external;


    /* ===============================================================
                    VALIDATOR MANAGEMENT
       =============================================================== */

    function registerValidator(
        address validator
    )
        external;


    /* ===============================================================
                    TRANSACTION REGISTRATION
       =============================================================== */

    function submitTransaction(
        string calldata prosumerId,
        uint256 feederId,
        uint256 powerKW,
        uint256 voltagePU,
        uint256 lossIndex,
        uint256 curtailmentIndex,
        uint256 carbonProxy
    )
        external
        returns (
            uint256 transactionId
        );


    /* ===============================================================
                        TRUST EVALUATION
       =============================================================== */

    /**
     * @notice Records the trust result generated by the
     *         off-chain GreenTrustChain trust engine.
     *
     * @param transactionId Blockchain transaction identifier.
     * @param trustScore Normalized trust score scaled to TRUST_SCALE.
     * @param datasetHash Hash identifying the dataset version.
     * @param modelHash Hash identifying the trust-model implementation.
     * @param modelVersion Version of the trust model.
     * @param inferenceTimestamp Time at which the trust decision was generated.
     */
    function updateTrustScore(
        uint256 transactionId,
        uint256 trustScore,
        bytes32 datasetHash,
        bytes32 modelHash,
        string calldata modelVersion,
        uint256 inferenceTimestamp
    )
        external;


    /* ===============================================================
                    VERIFICATION AND EXECUTION
       =============================================================== */

    function executeTransaction(
        uint256 transactionId
    )
        external;


    /* ===============================================================
                        GOVERNANCE
       =============================================================== */

    function updateGovernanceParameters(
        uint256 standardThreshold,
        uint256 enhancedThreshold,
        uint256 criticalThreshold,
        uint256 learningRate
    )
        external;


    function updateValidatorReputation(
        address validator,
        uint256 reputation
    )
        external;


    function governanceFeedback(
        uint256 transactionId
    )
        external;


    /* ===============================================================
                        CONTRACT CONTROL
       =============================================================== */

    function pauseContract()
        external;


    function unpauseContract()
        external;


    /* ===============================================================
                            READ API
       =============================================================== */

    function getTransaction(
        uint256 transactionId
    )
        external
        view
        returns (
            EnergyTransaction memory
        );


    function getGovernanceParameters()
        external
        view
        returns (
            GovernanceParameters memory
        );


    function getNetworkStatistics()
        external
        view
        returns (
            NetworkStatistics memory
        );


    function getParticipantTransactions(
        address participant
    )
        external
        view
        returns (
            uint256[] memory
        );


    function totalTransactions()
        external
        view
        returns (
            uint256
        );


    function averageTrust()
        external
        view
        returns (
            uint256
        );


    function contractVersion()
        external
        view
        returns (
            string memory
        );
}