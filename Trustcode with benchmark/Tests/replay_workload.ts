import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import csv from "csv-parser";

type ModelName =
    | "deterministic"
    | "trust_only"
    | "energy_aware"
    | "greentrustchain";

interface DatasetRow {
    rowId: number;
    prosumerId: string;
    feederId: number;
    powerKW: number;
    voltagePU: number;
    lossIndex: number;
    curtailmentIndex: number;
    carbonProxy: number;
    trustScore?: number;
}

interface ExperimentRecord {
    model: ModelName;

    datasetRowId: number;

    transactionId: string;

    transactionHash: string;

    blockNumber: number;

    gasUsed: string;

    gasPriceWei: string;

    gasCostWei: string;

    submittedAt: string;

    confirmedAt: string;

    confirmationLatencyMs: number;

    status: "success" | "failed";

    contractAddress: string;

    prosumerId: string;

    feederId: number;

    powerKW: number;

    trustScore?: number;
}


/* ================================================================
                        CONFIGURATION
   ================================================================ */

const DATASET_PATH =
    path.join(
        process.cwd(),
        "data",
        "raw",
        "GSCROF_benchmark_95556.csv"
    );

const RESULT_DIRECTORY =
    path.join(
        process.cwd(),
        "results",
        "raw"
    );

const DEFAULT_WORKLOAD_SIZE = 100;


/* ================================================================
                        DATASET LOADER
   ================================================================ */

async function loadDataset(
    limit: number
): Promise<DatasetRow[]> {

    return new Promise(
        (resolve, reject) => {

            const rows: DatasetRow[] = [];

            if (!fs.existsSync(DATASET_PATH)) {
                reject(
                    new Error(
                        `Dataset not found: ${DATASET_PATH}`
                    )
                );

                return;
            }

            fs.createReadStream(DATASET_PATH)
                .pipe(csv())
                .on(
                    "data",
                    (raw: Record<string, string>) => {

                        if (
                            rows.length >= limit
                        ) {
                            return;
                        }

                        /*
                         * ------------------------------------------------
                         * IMPORTANT
                         * ------------------------------------------------
                         *
                         * The column names below must exactly match
                         * the validated dataset schema.
                         *
                         * Do not silently rename or invent columns.
                         */

                        rows.push({

                            rowId:
                                Number(
                                    raw.row_id ??
                                    rows.length
                                ),

                            prosumerId:
                                String(
                                    raw.prosumer_id
                                ),

                            feederId:
                                Number(
                                    raw.feeder_id
                                ),

                            powerKW:
                                Number(
                                    raw.power_kw
                                ),

                            voltagePU:
                                Number(
                                    raw.voltage_pu
                                ),

                            lossIndex:
                                Number(
                                    raw.loss_index
                                ),

                            curtailmentIndex:
                                Number(
                                    raw.curtailment_index
                                ),

                            carbonProxy:
                                Number(
                                    raw.carbon_proxy
                                ),

                            trustScore:
                                raw.trust_score !== undefined
                                    ? Number(
                                        raw.trust_score
                                    )
                                    : undefined
                        });
                    }
                )
                .on(
                    "end",
                    () => resolve(rows)
                )
                .on(
                    "error",
                    reject
                );
        }
    );
}


/* ================================================================
                    DATASET VALIDATION
   ================================================================ */

function validateDataset(
    rows: DatasetRow[]
): void {

    if (rows.length === 0) {

        throw new Error(
            "Dataset contains no usable records."
        );
    }

    for (
        const row of rows
    ) {

        if (
            !row.prosumerId
        ) {

            throw new Error(
                `Missing prosumer ID at row ${row.rowId}`
            );
        }

        if (
            !Number.isFinite(
                row.feederId
            )
        ) {

            throw new Error(
                `Invalid feeder ID at row ${row.rowId}`
            );
        }

        if (
            !Number.isFinite(
                row.powerKW
            )
        ) {

            throw new Error(
                `Invalid power value at row ${row.rowId}`
            );
        }

        if (
            !Number.isFinite(
                row.voltagePU
            )
        ) {

            throw new Error(
                `Invalid voltage value at row ${row.rowId}`
            );
        }

        if (
            row.trustScore !== undefined &&
            (
                row.trustScore < 0 ||
                row.trustScore > 10_000
            )
        ) {

            throw new Error(
                `Trust score outside [0,10000] at row ${row.rowId}`
            );
        }
    }
}


/* ================================================================
                    DATASET FINGERPRINT
   ================================================================ */

function calculateDatasetHash(): string {

    const file =
        fs.readFileSync(
            DATASET_PATH
        );

    return crypto
        .createHash("sha256")
        .update(file)
        .digest("hex");
}


/* ================================================================
                    NUMBER NORMALIZATION
   ================================================================ */

function scaledInteger(
    value: number,
    scale: number
): bigint {

    if (
        !Number.isFinite(value)
    ) {

        throw new Error(
            `Cannot scale invalid number: ${value}`
        );
    }

    return BigInt(
        Math.round(
            value * scale
        )
    );
}


/* ================================================================
                TRANSACTION GAS INFORMATION
   ================================================================ */

async function getGasInformation(
    receipt: any
) {

    const gasUsed =
        receipt.gasUsed;

    const gasPrice =
        receipt.gasPrice ??
        receipt.effectiveGasPrice;

    if (
        gasPrice === undefined
    ) {

        throw new Error(
            "Gas price unavailable from transaction receipt."
        );
    }

    const gasCost =
        gasUsed * gasPrice;

    return {

        gasUsed:
            gasUsed.toString(),

        gasPriceWei:
            gasPrice.toString(),

        gasCostWei:
            gasCost.toString()
    };
}


/* ================================================================
                    GENERIC CSV WRITER
   ================================================================ */

function writeResults(
    records: ExperimentRecord[],
    filename: string
): void {

    fs.mkdirSync(
        RESULT_DIRECTORY,
        {
            recursive: true
        }
    );

    const header = [
        "model",
        "datasetRowId",
        "transactionId",
        "transactionHash",
        "blockNumber",
        "gasUsed",
        "gasPriceWei",
        "gasCostWei",
        "submittedAt",
        "confirmedAt",
        "confirmationLatencyMs",
        "status",
        "contractAddress",
        "prosumerId",
        "feederId",
        "powerKW",
        "trustScore"
    ];

    const lines = [
        header.join(",")
    ];

    for (
        const record of records
    ) {

        lines.push(
            [
                record.model,
                record.datasetRowId,
                record.transactionId,
                record.transactionHash,
                record.blockNumber,
                record.gasUsed,
                record.gasPriceWei,
                record.gasCostWei,
                record.submittedAt,
                record.confirmedAt,
                record.confirmationLatencyMs,
                record.status,
                record.contractAddress,
                record.prosumerId,
                record.feederId,
                record.powerKW,
                record.trustScore ?? ""
            ]
                .map(
                    value =>
                        `"${String(value).replace(
                            /"/g,
                            '""'
                        )}"`
                )
                .join(",")
        );
    }

    fs.writeFileSync(
        path.join(
            RESULT_DIRECTORY,
            filename
        ),
        lines.join("\n")
    );
}


/* ================================================================
                DETERMINISTIC BASELINE REPLAY
   ================================================================ */

async function replayDeterministic(
    rows: DatasetRow[],
    participant: any,
    validator: any
): Promise<ExperimentRecord[]> {

    const contract =
        await ethers.getContractAt(
            "DeterministicBaseline",
            process.env.DETERMINISTIC_ADDRESS!
        );

    const records: ExperimentRecord[] = [];

    for (
        const row of rows
    ) {

        const start =
            Date.now();

        const tx =
            await contract
                .connect(participant)
                .submitTransaction(
                    row.prosumerId,
                    row.feederId,
                    scaledInteger(
                        row.powerKW,
                        1_000
                    ),
                    scaledInteger(
                        row.voltagePU,
                        1_000
                    ),
                    scaledInteger(
                        row.lossIndex,
                        1_000
                    ),
                    scaledInteger(
                        row.curtailmentIndex,
                        1_000
                    ),
                    scaledInteger(
                        row.carbonProxy,
                        1_000
                    )
                );

        const submissionReceipt =
            await tx.wait();

        const executionStart =
            Date.now();

        const executeTx =
            await contract
                .connect(validator)
                .executeTransaction(
                    row.rowId
                );

        const receipt =
            await executeTx.wait();

        const confirmedAt =
            Date.now();

        const gas =
            await getGasInformation(
                receipt
            );

        records.push({

            model:
                "deterministic",

            datasetRowId:
                row.rowId,

            transactionId:
                row.rowId.toString(),

            transactionHash:
                executeTx.hash,

            blockNumber:
                receipt.blockNumber,

            gasUsed:
                gas.gasUsed,

            gasPriceWei:
                gas.gasPriceWei,

            gasCostWei:
                gas.gasCostWei,

            submittedAt:
                new Date(
                    start
                ).toISOString(),

            confirmedAt:
                new Date(
                    confirmedAt
                ).toISOString(),

            confirmationLatencyMs:
                confirmedAt -
                executionStart,

            status:
                receipt.status === 1
                    ? "success"
                    : "failed",

            contractAddress:
                await contract.getAddress(),

            prosumerId:
                row.prosumerId,

            feederId:
                row.feederId,

            powerKW:
                row.powerKW
        });

        /*
         * submissionReceipt is deliberately retained so the
         * experiment can later report submission and execution
         * gas separately.
         */
        void submissionReceipt;
    }

    return records;
}


/* ================================================================
                        MAIN EXPERIMENT
   ================================================================ */

async function main() {

    console.log(
        "\n=============================================="
    );

    console.log(
        " GreenTrustChain Workload Replay"
    );

    console.log(
        "==============================================\n"
    );


    const workloadSize =
        Number(
            process.env.WORKLOAD_SIZE ??
            DEFAULT_WORKLOAD_SIZE
        );


    console.log(
        `Workload size: ${workloadSize}`
    );

    console.log(
        `Dataset: ${DATASET_PATH}`
    );


    /*
     * ------------------------------------------------------------
     * Dataset
     * ------------------------------------------------------------
     */

    const rows =
        await loadDataset(
            workloadSize
        );

    validateDataset(
        rows
    );


    const datasetHash =
        calculateDatasetHash();

    console.log(
        `Dataset SHA-256: ${datasetHash}`
    );


    /*
     * ------------------------------------------------------------
     * Signers
     * ------------------------------------------------------------
     */

    const [
        deployer,
        participant,
        validator
    ] =
        await ethers.getSigners();


    console.log(
        `Participant: ${participant.address}`
    );

    console.log(
        `Validator:   ${validator.address}`
    );


    /*
     * ------------------------------------------------------------
     * Deterministic baseline
     * ------------------------------------------------------------
     */

    if (
        !process.env.DETERMINISTIC_ADDRESS
    ) {

        throw new Error(
            "DETERMINISTIC_ADDRESS is not defined."
        );
    }


    const deterministicResults =
        await replayDeterministic(
            rows,
            participant,
            validator
        );


    writeResults(
        deterministicResults,
        "deterministic.csv"
    );


    console.log(
        "\nDeterministic baseline replay completed."
    );


    /*
     * ------------------------------------------------------------
     * Future replay stages
     * ------------------------------------------------------------
     *
     * TrustOnly, EnergyAware and GreenTrustChain are deliberately
     * not executed in this first implementation until their exact
     * deployed ABI and trust-engine interface are frozen.
     *
     * This avoids silently applying an incorrect trust calculation
     * to the experimental dataset.
     */

    void deployer;

    console.log(
        "\nRaw deterministic results written to:"
    );

    console.log(
        path.join(
            RESULT_DIRECTORY,
            "deterministic.csv"
        )
    );
}


main().catch(
    error => {

        console.error(
            "\nWorkload replay failed:"
        );

        console.error(
            error
        );

        process.exitCode = 1;
    }
);