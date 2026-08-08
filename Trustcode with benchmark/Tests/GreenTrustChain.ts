import { expect } from "chai";
import { ethers } from "hardhat";
import type { Contract } from "ethers";

describe("GreenTrustChain", function () {
    let greenTrustChain: Contract;

    let admin: any;
    let participant: any;
    let validator: any;
    let otherAccount: any;

    const TRUST_SCALE = 10_000;

    /*
     * Fixed-point trust examples:
     *
     * 0.90 = 9000
     * 0.75 = 7500
     * 0.50 = 5000
     */
    const HIGH_TRUST = 9000;
    const MEDIUM_TRUST = 7500;
    const LOW_TRUST = 5000;

    beforeEach(async function () {
        [
            admin,
            participant,
            validator,
            otherAccount
        ] = await ethers.getSigners();

        const GreenTrustChain =
            await ethers.getContractFactory(
                "GreenTrustChain"
            );

        greenTrustChain =
            await GreenTrustChain.deploy();

        await greenTrustChain.waitForDeployment();

        /*
         * Register experimental participant.
         */
        await greenTrustChain
            .connect(admin)
            .registerParticipant(
                participant.address
            );

        /*
         * Register independent validator.
         */
        await greenTrustChain
            .connect(admin)
            .registerValidator(
                validator.address
            );
    });


    /* ============================================================
                            DEPLOYMENT
       ============================================================ */

    describe("Deployment", function () {

        it(
            "should deploy successfully",
            async function () {

                const address =
                    await greenTrustChain.getAddress();

                expect(address).to.not.equal(
                    ethers.ZeroAddress
                );
            }
        );


        it(
            "should expose the expected contract version",
            async function () {

                const version =
                    await greenTrustChain
                        .contractVersion();

                expect(version).to.be.a("string");

                expect(version).to.contain(
                    "GreenTrustChain"
                );
            }
        );

    });


    /* ============================================================
                    PARTICIPANT AND VALIDATOR
       ============================================================ */

    describe(
        "Participant and Validator Management",
        function () {

            it(
                "should register a participant",
                async function () {

                    const hasRole =
                        await greenTrustChain.hasRole(
                            await greenTrustChain.PARTICIPANT_ROLE(),
                            participant.address
                        );

                    expect(hasRole).to.equal(true);
                }
            );


            it(
                "should register a validator",
                async function () {

                    const registered =
                        await greenTrustChain
                            .registeredValidators(
                                validator.address
                            );

                    expect(registered).to.equal(true);
                }
            );


            it(
                "should reject zero participant address",
                async function () {

                    await expect(
                        greenTrustChain
                            .connect(admin)
                            .registerParticipant(
                                ethers.ZeroAddress
                            )
                    ).to.be.reverted;
                }
            );

        }
    );


    /* ============================================================
                        TRANSACTION SUBMISSION
       ============================================================ */

    describe(
        "Energy Transaction",
        function () {

            it(
                "should submit an energy transaction",
                async function () {

                    const tx =
                        await greenTrustChain
                            .connect(participant)
                            .submitTransaction(
                                "PROSUMER_001",
                                1,
                                1250,
                                998,
                                25,
                                10,
                                150
                            );

                    const receipt =
                        await tx.wait();

                    expect(receipt).to.not.equal(
                        null
                    );

                    const stored =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        stored.sender
                    ).to.equal(
                        participant.address
                    );

                    expect(
                        stored.prosumerId
                    ).to.equal(
                        "PROSUMER_001"
                    );

                    expect(
                        stored.feederId
                    ).to.equal(1);

                    expect(
                        stored.powerKW
                    ).to.equal(1250);

                    expect(
                        stored.committed
                    ).to.equal(false);
                }
            );


            it(
                "should reject transaction from an unregistered participant",
                async function () {

                    await expect(
                        greenTrustChain
                            .connect(otherAccount)
                            .submitTransaction(
                                "UNREGISTERED",
                                1,
                                1250,
                                998,
                                25,
                                10,
                                150
                            )
                    ).to.be.reverted;
                }
            );

        }
    );


    /* ============================================================
                        TRUST EVALUATION
       ============================================================ */

    describe(
        "Trust Evaluation",
        function () {

            beforeEach(
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_001",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );
                }
            );


            it(
                "should store a normalized trust score",
                async function () {

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "GSCROF_TEST_DATASET_V1"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MTEM_TEST_MODEL_V1"
                            )
                        );

                    await expect(
                        greenTrustChain
                            .connect(validator)
                            .updateTrustScore(
                                0,
                                HIGH_TRUST,
                                datasetHash,
                                modelHash,
                                "MTEM-v1.0",
                                1_753_000_000
                            )
                    ).to.not.be.reverted;

                    const stored =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        stored.trustScore
                    ).to.equal(HIGH_TRUST);

                    expect(
                        stored.trustEvaluated
                    ).to.equal(true);
                }
            );


            it(
                "should reject trust scores above the defined scale",
                async function () {

                    const invalidTrust =
                        TRUST_SCALE + 1;

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "TEST_DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "TEST_MODEL"
                            )
                        );

                    await expect(
                        greenTrustChain
                            .connect(validator)
                            .updateTrustScore(
                                0,
                                invalidTrust,
                                datasetHash,
                                modelHash,
                                "MTEM-v1.0",
                                1_753_000_000
                            )
                    ).to.be.reverted;
                }
            );

        }
    );


    /* ============================================================
                    VERIFICATION CLASSIFICATION
       ============================================================ */

    describe(
        "Verification Classification",
        function () {

            it(
                "should classify high-trust transaction as standard",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_HIGH",
                            1,
                            1200,
                            1000,
                            20,
                            5,
                            100
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MODEL"
                            )
                        );

                    await greenTrustChain
                        .connect(validator)
                        .updateTrustScore(
                            0,
                            HIGH_TRUST,
                            datasetHash,
                            modelHash,
                            "MTEM-v1.0",
                            1_753_000_000
                        );

                    const txn =
                        await greenTrustChain
                            .getTransaction(0);

                    /*
                     * Enum:
                     *
                     * Standard = 0
                     * Enhanced = 1
                     * Critical = 2
                     */
                    expect(
                        txn.verificationLevel
                    ).to.equal(0);
                }
            );


            it(
                "should classify medium-trust transaction as enhanced",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_MEDIUM",
                            1,
                            1200,
                            1000,
                            20,
                            5,
                            100
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MODEL"
                            )
                        );

                    await greenTrustChain
                        .connect(validator)
                        .updateTrustScore(
                            0,
                            MEDIUM_TRUST,
                            datasetHash,
                            modelHash,
                            "MTEM-v1.0",
                            1_753_000_000
                        );

                    const txn =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        txn.verificationLevel
                    ).to.equal(1);
                }
            );

        }
    );


    /* ============================================================
                        EXECUTION
       ============================================================ */

    describe(
        "Trust-Driven Execution",
        function () {

            it(
                "should approve a high-trust transaction",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_EXEC",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MODEL"
                            )
                        );

                    await greenTrustChain
                        .connect(validator)
                        .updateTrustScore(
                            0,
                            HIGH_TRUST,
                            datasetHash,
                            modelHash,
                            "MTEM-v1.0",
                            1_753_000_000
                        );

                    const execution =
                        await greenTrustChain
                            .connect(validator)
                            .executeTransaction(0);

                    const receipt =
                        await execution.wait();

                    expect(receipt).to.not.equal(
                        null
                    );

                    const txn =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        txn.committed
                    ).to.equal(true);

                    /*
                     * Approved = 1
                     */
                    expect(
                        txn.status
                    ).to.equal(1);
                }
            );


            it(
                "should record the validator responsible for execution",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_VALIDATOR",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MODEL"
                            )
                        );

                    await greenTrustChain
                        .connect(validator)
                        .updateTrustScore(
                            0,
                            HIGH_TRUST,
                            datasetHash,
                            modelHash,
                            "MTEM-v1.0",
                            1_753_000_000
                        );

                    await greenTrustChain
                        .connect(validator)
                        .executeTransaction(0);

                    const txn =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        txn.validator
                    ).to.equal(
                        validator.address
                    );
                }
            );

        }
    );


    /* ============================================================
                        PROVENANCE
       ============================================================ */

    describe(
        "Trust Provenance",
        function () {

            it(
                "should preserve dataset and model hashes",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_PROVENANCE",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "GSCROF-v1"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MTEM-v1"
                            )
                        );

                    await greenTrustChain
                        .connect(validator)
                        .updateTrustScore(
                            0,
                            HIGH_TRUST,
                            datasetHash,
                            modelHash,
                            "MTEM-v1.0",
                            1_753_000_000
                        );

                    const txn =
                        await greenTrustChain
                            .getTransaction(0);

                    expect(
                        txn.datasetHash
                    ).to.equal(
                        datasetHash
                    );

                    expect(
                        txn.modelHash
                    ).to.equal(
                        modelHash
                    );

                    expect(
                        txn.modelVersion
                    ).to.equal(
                        "MTEM-v1.0"
                    );
                }
            );

        }
    );


    /* ============================================================
                        STATISTICS
       ============================================================ */

    describe(
        "Network Statistics",
        function () {

            it(
                "should update transaction statistics",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_STATS",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    const stats =
                        await greenTrustChain
                            .getNetworkStatistics();

                    expect(
                        stats.totalTransactions
                    ).to.equal(1);

                    expect(
                        stats.pendingTransactions
                    ).to.equal(1);
                }
            );

        }
    );


    /* ============================================================
                        PAUSE CONTROL
       ============================================================ */

    describe(
        "Emergency Control",
        function () {

            it(
                "should pause transaction processing",
                async function () {

                    await greenTrustChain
                        .connect(admin)
                        .pauseContract();

                    await expect(
                        greenTrustChain
                            .connect(participant)
                            .submitTransaction(
                                "PAUSED_TEST",
                                1,
                                1250,
                                998,
                                25,
                                10,
                                150
                            )
                    ).to.be.reverted;
                }
            );


            it(
                "should resume transaction processing",
                async function () {

                    await greenTrustChain
                        .connect(admin)
                        .pauseContract();

                    await greenTrustChain
                        .connect(admin)
                        .unpauseContract();

                    await expect(
                        greenTrustChain
                            .connect(participant)
                            .submitTransaction(
                                "RESUMED_TEST",
                                1,
                                1250,
                                998,
                                25,
                                10,
                                150
                            )
                    ).to.not.be.reverted;
                }
            );

        }
    );


    /* ============================================================
                    ACCESS CONTROL VALIDATION
       ============================================================ */

    describe(
        "Access Control",
        function () {

            it(
                "should reject unauthorized trust updates",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_ACCESS",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    const datasetHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "DATASET"
                            )
                        );

                    const modelHash =
                        ethers.keccak256(
                            ethers.toUtf8Bytes(
                                "MODEL"
                            )
                        );

                    await expect(
                        greenTrustChain
                            .connect(otherAccount)
                            .updateTrustScore(
                                0,
                                HIGH_TRUST,
                                datasetHash,
                                modelHash,
                                "MTEM-v1.0",
                                1_753_000_000
                            )
                    ).to.be.reverted;
                }
            );


            it(
                "should reject unauthorized execution",
                async function () {

                    await greenTrustChain
                        .connect(participant)
                        .submitTransaction(
                            "PROSUMER_EXEC_ACCESS",
                            1,
                            1250,
                            998,
                            25,
                            10,
                            150
                        );

                    await expect(
                        greenTrustChain
                            .connect(otherAccount)
                            .executeTransaction(0)
                    ).to.be.reverted;
                }
            );

        }
    );
});