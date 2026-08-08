// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * ------------------------------------------------------------------------
 * GreenTrustChain
 * A Trust-Driven and Energy-Efficient Smart Contract Framework
 * for Sustainable Blockchain-Based Energy Markets
 *
 * Version      : 1.0
 * Solidity     : 0.8.24
 * Framework    : Hardhat
 * License      : MIT
 * ------------------------------------------------------------------------
 */

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract GreenTrustChain is
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    using Counters for Counters.Counter;

    /* ===============================================================
                            ROLE DEFINITIONS
       ===============================================================*/

    bytes32 public constant VALIDATOR_ROLE =
        keccak256("VALIDATOR_ROLE");

    bytes32 public constant GOVERNANCE_ROLE =
        keccak256("GOVERNANCE_ROLE");

    bytes32 public constant PARTICIPANT_ROLE =
        keccak256("PARTICIPANT_ROLE");

    /* ===============================================================
                            COUNTERS
       ===============================================================*/

    Counters.Counter private transactionCounter;

    /* ===============================================================
                            ENUMS
       ===============================================================*/

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
       ===============================================================*/

    struct EnergyTransaction {

        uint256 transactionId;

        address sender;

        string prosumerId;

        uint256 feederId;

        uint256 powerKW;

        uint256 voltagePU;

        uint256 lossIndex;

        uint256 carbonProxy;

        uint256 timestamp;

        uint256 trustScore;

        VerificationLevel verificationLevel;

        TransactionStatus status;

        bool committed;
    }

    /* ===============================================================
                        GOVERNANCE STRUCTURE
       ===============================================================*/

    struct GovernanceParameters {

        uint256 standardThreshold;

        uint256 enhancedThreshold;

        uint256 criticalThreshold;

        uint256 governanceVersion;

        uint256 lastUpdated;
    }

    /* ===============================================================
                            NETWORK METRICS
       ===============================================================*/

    struct NetworkStatistics {

        uint256 totalTransactions;

        uint256 approvedTransactions;

        uint256 rejectedTransactions;

        uint256 pendingTransactions;

        uint256 cumulativeTrust;

        uint256 averageTrust;

        uint256 totalValidators;

        uint256 lastBlockUpdated;
    }

    /* ===============================================================
                        STATE VARIABLES
       ===============================================================*/

    mapping(uint256 => EnergyTransaction)
        private transactions;

    mapping(address => bool)
        public registeredValidators;

    mapping(address => uint256)
        public validatorReputation;

    GovernanceParameters public governance;

    NetworkStatistics public statistics;

    /* ===============================================================
                        TRUST PARAMETERS
       ===============================================================*/

    uint256 public historicalWeight = 25;

    uint256 public consistencyWeight = 25;

    uint256 public communicationWeight = 25;

    uint256 public contextualWeight = 25;

    uint256 public constant TRUST_SCALE = 100;

    /* ===============================================================
                            EVENTS
       ===============================================================*/

    event TransactionSubmitted(

        uint256 indexed transactionId,

        address indexed sender,

        uint256 timestamp
    );

    event TrustScoreUpdated(

        uint256 indexed transactionId,

        uint256 trustScore
    );

    event VerificationAssigned(

        uint256 indexed transactionId,

        VerificationLevel level
    );

    event TransactionExecuted(

        uint256 indexed transactionId,

        TransactionStatus status
    );

    event GovernanceUpdated(

        uint256 version,

        uint256 timestamp
    );

    event ValidatorRegistered(

        address validator
    );

    /* ===============================================================
                            CONSTRUCTOR
       ===============================================================*/

    constructor() {

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _grantRole(GOVERNANCE_ROLE, msg.sender);

        _grantRole(VALIDATOR_ROLE, msg.sender);

        governance = GovernanceParameters({

            standardThreshold: 80,

            enhancedThreshold: 60,

            criticalThreshold: 40,

            governanceVersion: 1,

            lastUpdated: block.timestamp
        });

        statistics.totalValidators = 1;
    }

    /* ===============================================================
                            MODIFIERS
       ===============================================================*/

    modifier onlyValidator() {

        require(

            hasRole(VALIDATOR_ROLE, msg.sender),

            "Validator access required"

        );

        _;
    }

    modifier onlyGovernance() {

        require(

            hasRole(GOVERNANCE_ROLE, msg.sender),

            "Governance access required"

        );

        _;
    }

    modifier transactionExists(
        uint256 transactionId
    ) {

        require(

            transactionId <
                transactionCounter.current(),

            "Invalid transaction"

        );

        _;
    }
modifier transactionExists(uint256 transactionId) {
    require(
        transactionId < transactionCounter.current(),
        "Invalid transaction"
    );
    _;
}
    /* ===============================================================
                    PARTICIPANT MANAGEMENT
    ===============================================================*/

    /**
     * @dev Register a new participant in the GreenTrustChain network.
     */
    function registerParticipant(
        address participant
    )
        external
        onlyGovernance
    {
        require(
            participant != address(0),
            "Invalid participant address"
        );

        require(
            !hasRole(PARTICIPANT_ROLE, participant),
            "Participant already registered"
        );

        _grantRole(
            PARTICIPANT_ROLE,
            participant
        );
    }


    /**
     * @dev Register a validator responsible for transaction verification.
     */
    function registerValidator(
        address validator
    )
        external
        onlyGovernance
    {
        require(
            validator != address(0),
            "Invalid validator address"
        );

        require(
            !registeredValidators[validator],
            "Validator already exists"
        );

        registeredValidators[validator] = true;

        validatorReputation[validator] = 100;

        _grantRole(
            VALIDATOR_ROLE,
            validator
        );

        statistics.totalValidators++;

        emit ValidatorRegistered(
            validator
        );
    }

    /* ===============================================================
                        TRANSACTION SUBMISSION
    ===============================================================*/

    /**
     * @dev Submit an energy transaction before trust evaluation.
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
    {

        transactionCounter.increment();

        uint256 txId =
            transactionCounter.current() - 1;

        transactions[txId] = EnergyTransaction({

            transactionId: txId,

            sender: msg.sender,

            prosumerId: prosumerId,

            feederId: feederId,

            powerKW: powerKW,

            voltagePU: voltagePU,

            lossIndex: lossIndex,

            carbonProxy: carbonProxy,

            timestamp: block.timestamp,

            trustScore: 0,

            verificationLevel:
                VerificationLevel.Standard,

            status:
                TransactionStatus.Pending,

            committed: false
        });

        statistics.totalTransactions++;

        statistics.pendingTransactions++;

        emit TransactionSubmitted(

            txId,

            msg.sender,

            block.timestamp
        );
    }
/* ===============================================================
                    TRUST MANAGEMENT
===============================================================*/

/**
 * @notice Updates trust score generated by the off-chain trust engine.
 * @dev Only validators can assign trust scores.
 */
function updateTrustScore(

    uint256 transactionId,

    uint256 trustScore

)
    external
    onlyValidator
    transactionExists(transactionId)
{

    require(

        trustScore <= TRUST_SCALE,

        "Trust score exceeds limit"

    );

    EnergyTransaction storage txn =
        transactions[transactionId];

    require(

        txn.status ==
            TransactionStatus.Pending,

        "Transaction already processed"

    );

    txn.trustScore = trustScore;

    statistics.cumulativeTrust += trustScore;

    statistics.averageTrust =
        statistics.cumulativeTrust /
        statistics.totalTransactions;

    emit TrustScoreUpdated(

        transactionId,

        trustScore

    );

    assignVerificationLevel(
        transactionId
    );
}


/* ===============================================================
                VERIFICATION ASSIGNMENT
===============================================================*/

function assignVerificationLevel(

    uint256 transactionId

)
    internal
{

    EnergyTransaction storage txn =
        transactions[transactionId];

    if(

        txn.trustScore >=
        governance.standardThreshold

    ){

        txn.verificationLevel =
            VerificationLevel.Standard;

    }

    else if(

        txn.trustScore >=
        governance.enhancedThreshold

    ){

        txn.verificationLevel =
            VerificationLevel.Enhanced;

    }

    else{

        txn.verificationLevel =
            VerificationLevel.Critical;

    }

    emit VerificationAssigned(

        transactionId,

        txn.verificationLevel

    );
}


/* ===============================================================
                    SMART CONTRACT EXECUTION
===============================================================*/

function executeTransaction(

    uint256 transactionId

)
    external
    onlyValidator
    transactionExists(transactionId)
    whenNotPaused
    nonReentrant
{

    EnergyTransaction storage txn =
        transactions[transactionId];

    require(

        txn.status ==
            TransactionStatus.Pending,

        "Already executed"

    );

    if(

        txn.verificationLevel ==
        VerificationLevel.Standard

    ){

        txn.status =
            TransactionStatus.Approved;

    }

    else if(

        txn.verificationLevel ==
        VerificationLevel.Enhanced

    ){

        if(txn.trustScore >= 70){

            txn.status =
                TransactionStatus.Approved;

        }

        else{

            txn.status =
                TransactionStatus.Rejected;

        }

    }

    else{

        txn.status =
            TransactionStatus.Rejected;

    }

    txn.committed = true;

    statistics.pendingTransactions--;

    if(

        txn.status ==
            TransactionStatus.Approved

    ){

        statistics.approvedTransactions++;

    }

    else{

        statistics.rejectedTransactions++;

    }

    emit TransactionExecuted(

        transactionId,

        txn.status

    );

}
/* ===============================================================
                    ADAPTIVE GOVERNANCE
===============================================================*/

/**
 * @notice Update governance thresholds.
 * @dev Only governance authority can modify thresholds.
 */
function updateGovernanceParameters(

    uint256 standardThreshold,
    uint256 enhancedThreshold,
    uint256 criticalThreshold

)
    external
    onlyGovernance
{

    require(
        standardThreshold > enhancedThreshold,
        "Invalid standard threshold"
    );

    require(
        enhancedThreshold > criticalThreshold,
        "Invalid enhanced threshold"
    );

    require(
        standardThreshold <= TRUST_SCALE,
        "Threshold exceeds trust scale"
    );

    governance.standardThreshold = standardThreshold;
    governance.enhancedThreshold = enhancedThreshold;
    governance.criticalThreshold = criticalThreshold;

    governance.governanceVersion += 1;
    governance.lastUpdated = block.timestamp;

    emit GovernanceUpdated(
        governance.governanceVersion,
        block.timestamp
    );
}


/**
 * @notice Update validator reputation.
 */
function updateValidatorReputation(

    address validator,
    uint256 reputation

)
    external
    onlyGovernance
{

    require(
        registeredValidators[validator],
        "Validator not registered"
    );

    require(
        reputation <= TRUST_SCALE,
        "Invalid reputation"
    );

    validatorReputation[validator] = reputation;
}


/**
 * @notice Pause contract execution.
 */
function pauseContract()
    external
    onlyGovernance
{
    _pause();
}


/**
 * @notice Resume contract execution.
 */
function unpauseContract()
    external
    onlyGovernance
{
    _unpause();
}


/* ===============================================================
                    READ FUNCTIONS
===============================================================*/

/**
 * @notice Return a complete transaction.
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
 * @notice Return current governance parameters.
 */
function getGovernanceParameters()

    external
    view

    returns(

        GovernanceParameters memory

    )
{
    return governance;
}


/**
 * @notice Return overall network statistics.
 */
function getNetworkStatistics()

    external
    view

    returns(

        NetworkStatistics memory

    )
{
    return statistics;
}


/**
 * @notice Total transactions stored.
 */
function totalTransactions()

    external
    view

    returns(uint256)
{
    return transactionCounter.current();
}


/**
 * @notice Average trust score.
 */
function averageTrust()

    external
    view

    returns(uint256)
{

    if(statistics.totalTransactions == 0){

        return 0;

    }

    return
        statistics.cumulativeTrust /
        statistics.totalTransactions;
}


/* ===============================================================
                GOVERNANCE FEEDBACK
===============================================================*/

/**
 * @notice Adaptive governance feedback.
 * @dev Adjusts validator reputation using execution outcomes.
 */
function governanceFeedback(

    uint256 transactionId

)
    external
    onlyGovernance
    transactionExists(transactionId)
{

    EnergyTransaction storage txn =
        transactions[transactionId];

    if(
        txn.status ==
        TransactionStatus.Approved
    ){

        if(
            validatorReputation[txn.sender]
                < TRUST_SCALE
        ){

            validatorReputation[txn.sender]++;

        }

    }

    else{

        if(
            validatorReputation[txn.sender]
                > 0
        ){

            validatorReputation[txn.sender]--;

        }

    }

}


/* ===============================================================
                    VERSION INFORMATION
===============================================================*/

function contractVersion()

    external
    pure

    returns(string memory)
{

    return
        "GreenTrustChain v1.0";

}