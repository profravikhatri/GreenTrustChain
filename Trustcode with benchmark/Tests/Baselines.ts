import { expect } from "chai";
import { ethers } from "hardhat";
import type { Contract } from "ethers";

describe("GreenTrustChain Benchmark Baselines", function () {
    let deterministic: Contract;
    let trustOnly: Contract;
    let energyAware: Contract;

    let admin: any;
    let participant: any;
    let validator: any;

    const HIGH_TRUST = 9000;

    /*
     * Identical transaction payload for controlled comparison.
     *
     * The same operational values are sent to every baseline.
     */
    const transactionData = {
        prosumerId: "PROSUMER_001",
        feederId: 1,
        powerKW: 1250,
        voltagePU: 998,
        lossIndex: 25,
        curtailmentIndex: 10,
        carbonProxy: 150
    };


    /* ============================================================
                            DEPLOYMENT
       ============================================================ */

    beforeEach(async function () {
        [
            admin,
            participant,
            validator
        ] = await ethers.getSigners();


        /*
         * --------------------------------------------------------
         * Deterministic baseline
         * --------------------------------------------------------
         */

        const Deterministic =
            await ethers.getContractFactory(
                "DeterministicBaseline"
            );

        deterministic =
            await Deterministic.deploy();

        await deterministic.waitForDeployment();


        /*
         * --------------------------------------------------------
         * Trust-only baseline
         * --------------------------------------------------------
         */

        const TrustOnly =
            await ethers.getContractFactory(
                "TrustOnlyBaseline"
            );

        trustOnly =
            await TrustOnly.deploy();

        await trustOnly.waitForDeployment();


        /*
         * --------------------------------------------------------
         * Energy-aware baseline
         * --------------------------------------------------------
         */

        const EnergyAware =
            await ethers.getContractFactory(
                "EnergyAwareBaseline"
            );

        energyAware =
            await EnergyAware.deploy();

        await energyAware.waitForDeployment();


        /*
         * --------------------------------------------------------
         * Register identical participants and validators
         * --------------------------------------------------------
         */

        await deterministic
            .connect(admin)
            .registerParticipant(
                participant.address
            );

        await deterministic
            .connect(admin)
            .registerValidator(
                validator.address
            );


        await trustOnly
            .connect(admin)
            .registerParticipant(
                participant.address
            );

        await trustOnly
            .connect(admin)
            .registerValidator(
                validator.address
            );


        await energyAware
            .connect(admin)
            .registerParticipant(
                participant.address
            );

        await energyAware
            .connect(admin)
            .registerValidator(
                validator.address
            );
    });


    /* ============================================================
                    DETERMINISTIC BASELINE
       ============================================================ */

    describe(
        "DeterministicBaseline",
        function () {

            it(
                "should submit and execute a transaction",
                async function () {

                    const submission =
                        await deterministic
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.lossIndex,
                                transactionData.curtailmentIndex,
                                transactionData.carbonProxy
                            );

                    const submissionReceipt =
                        await submission.wait();

                    expect(
                        submissionReceipt
                    ).to.not.equal(null);


                    const execution =
                        await deterministic
                            .connect(validator)
                            .executeTransaction(0);

                    const executionReceipt =
                        await execution.wait();

                    expect(
                        executionReceipt
                    ).to.not.equal(null);


                    const txn =
                        await deterministic
                            .getTransaction(0);

                    /*
                     * Approved = 1
                     */
                    expect(
                        txn.status
                    ).to.equal(1);

                    expect(
                        txn.committed
                    ).to.equal(true);
                }
            );


            it(
                "should expose measurable gas usage",
                async function () {

                    const submission =
                        await deterministic
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.lossIndex,
                                transactionData.curtailmentIndex,
                                transactionData.carbonProxy
                            );

                    const receipt =
                        await submission.wait();

                    expect(
                        receipt!.gasUsed
                    ).to.be.greaterThan(0);
                }
            );

        }
    );


    /* ============================================================
                        TRUST-ONLY BASELINE
       ============================================================ */

    describe(
        "TrustOnlyBaseline",
        function () {

            it(
                "should submit a transaction with a fixed trust score",
                async function () {

                    const submission =
                        await trustOnly
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.lossIndex,
                                transactionData.curtailmentIndex,
                                transactionData.carbonProxy,
                                HIGH_TRUST
                            );

                    const receipt =
                        await submission.wait();

                    expect(
                        receipt
                    ).to.not.equal(null);


                    const txn =
                        await trustOnly
                            .getTransaction(0);

                    expect(
                        txn.trustScore
                    ).to.equal(
                        HIGH_TRUST
                    );
                }
            );


            it(
                "should approve a high-trust transaction",
                async function () {

                    await trustOnly
                        .connect(participant)
                        .submitTransaction(
                            transactionData.prosumerId,
                            transactionData.feederId,
                            transactionData.powerKW,
                            transactionData.voltagePU,
                            transactionData.lossIndex,
                            transactionData.curtailmentIndex,
                            transactionData.carbonProxy,
                            HIGH_TRUST
                        );

                    const execution =
                        await trustOnly
                            .connect(validator)
                            .executeTransaction(0);

                    const receipt =
                        await execution.wait();

                    expect(
                        receipt
                    ).to.not.equal(null);


                    const txn =
                        await trustOnly
                            .getTransaction(0);

                    expect(
                        txn.status
                    ).to.equal(1);

                    expect(
                        txn.committed
                    ).to.equal(true);
                }
            );


            it(
                "should reject low-trust transactions",
                async function () {

                    const LOW_TRUST = 5000;

                    await trustOnly
                        .connect(participant)
                        .submitTransaction(
                            transactionData.prosumerId,
                            transactionData.feederId,
                            transactionData.powerKW,
                            transactionData.voltagePU,
                            transactionData.lossIndex,
                            transactionData.curtailmentIndex,
                            transactionData.carbonProxy,
                            LOW_TRUST
                        );

                    await trustOnly
                        .connect(validator)
                        .executeTransaction(0);

                    const txn =
                        await trustOnly
                            .getTransaction(0);

                    /*
                     * Rejected = 2
                     */
                    expect(
                        txn.status
                    ).to.equal(2);

                    expect(
                        txn.committed
                    ).to.equal(false);
                }
            );

        }
    );


    /* ============================================================
                    ENERGY-AWARE BASELINE
       ============================================================ */

    describe(
        "EnergyAwareBaseline",
        function () {

            it(
                "should execute the lightweight transaction path",
                async function () {

                    const submission =
                        await energyAware
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.carbonProxy
                            );

                    const submissionReceipt =
                        await submission.wait();

                    expect(
                        submissionReceipt
                    ).to.not.equal(null);


                    const execution =
                        await energyAware
                            .connect(validator)
                            .executeTransaction(0);

                    const executionReceipt =
                        await execution.wait();

                    expect(
                        executionReceipt
                    ).to.not.equal(null);


                    const txn =
                        await energyAware
                            .getTransaction(0);

                    expect(
                        txn.status
                    ).to.equal(1);

                    expect(
                        txn.committed
                    ).to.equal(true);
                }
            );


            it(
                "should support controlled batch execution",
                async function () {

                    /*
                     * Submit three identical transactions.
                     */

                    for (
                        let i = 0;
                        i < 3;
                        i++
                    ) {

                        await energyAware
                            .connect(participant)
                            .submitTransaction(
                                `PROSUMER_${i}`,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.carbonProxy
                            );
                    }


                    const batch =
                        await energyAware
                            .connect(validator)
                            .executeBatch(
                                [0, 1, 2]
                            );

                    const receipt =
                        await batch.wait();

                    expect(
                        receipt!.gasUsed
                    ).to.be.greaterThan(0);


                    const statistics =
                        await energyAware
                            .getNetworkStatistics();

                    expect(
                        statistics.totalCommitted
                    ).to.equal(3);
                }
            );

        }
    );


    /* ============================================================
                    CROSS-BASELINE COMPARISON
       ============================================================ */

    describe(
        "Controlled Comparison",
        function () {

            it(
                "should process the same workload across all baselines",
                async function () {

                    /*
                     * ------------------------------------------------
                     * Deterministic
                     * ------------------------------------------------
                     */

                    const dSubmit =
                        await deterministic
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.lossIndex,
                                transactionData.curtailmentIndex,
                                transactionData.carbonProxy
                            );

                    const dSubmitReceipt =
                        await dSubmit.wait();


                    const dExecute =
                        await deterministic
                            .connect(validator)
                            .executeTransaction(0);

                    const dExecuteReceipt =
                        await dExecute.wait();


                    /*
                     * ------------------------------------------------
                     * Trust-only
                     * ------------------------------------------------
                     */

                    const tSubmit =
                        await trustOnly
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.lossIndex,
                                transactionData.curtailmentIndex,
                                transactionData.carbonProxy,
                                HIGH_TRUST
                            );

                    const tSubmitReceipt =
                        await tSubmit.wait();


                    const tExecute =
                        await trustOnly
                            .connect(validator)
                            .executeTransaction(0);

                    const tExecuteReceipt =
                        await tExecute.wait();


                    /*
                     * ------------------------------------------------
                     * Energy-aware
                     * ------------------------------------------------
                     */

                    const eSubmit =
                        await energyAware
                            .connect(participant)
                            .submitTransaction(
                                transactionData.prosumerId,
                                transactionData.feederId,
                                transactionData.powerKW,
                                transactionData.voltagePU,
                                transactionData.carbonProxy
                            );

                    const eSubmitReceipt =
                        await eSubmit.wait();


                    const eExecute =
                        await energyAware
                            .connect(validator)
                            .executeTransaction(0);

                    const eExecuteReceipt =
                        await eExecute.wait();


                    /*
                     * ------------------------------------------------
                     * Verify successful commitment
                     * ------------------------------------------------
                     */

                    const dTxn =
                        await deterministic
                            .getTransaction(0);

                    const tTxn =
                        await trustOnly
                            .getTransaction(0);

                    const eTxn =
                        await energyAware
                            .getTransaction(0);


                    expect(
                        dTxn.committed
                    ).to.equal(true);

                    expect(
                        tTxn.committed
                    ).to.equal(true);

                    expect(
                        eTxn.committed
                    ).to.equal(true);


                    /*
                     * ------------------------------------------------
                     * Verify measurable gas values
                     * ------------------------------------------------
                     */

                    expect(
                        dSubmitReceipt!.gasUsed
                    ).to.be.greaterThan(0);

                    expect(
                        dExecuteReceipt!.gasUsed
                    ).to.be.greaterThan(0);

                    expect(
                        tSubmitReceipt!.gasUsed
                    ).to.be.greaterThan(0);

                    expect(
                        tExecuteReceipt!.gasUsed
                    ).to.be.greaterThan(0);

                    expect(
                        eSubmitReceipt!.gasUsed
                    ).to.be.greaterThan(0);

                    expect(
                        eExecuteReceipt!.gasUsed
                    ).to.be.greaterThan(0);
                }
            );

        }
    );
});