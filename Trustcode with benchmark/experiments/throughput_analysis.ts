import fs from "fs";
import path from "path";

/**
 * GreenTrustChain
 * Throughput Analysis
 *
 * Purpose:
 *   Calculate blockchain workload throughput from canonical
 *   transaction receipts.
 *
 * This script DOES NOT execute blockchain transactions.
 *
 * Primary measures:
 *
 *   1. Attempted TPS
 *   2. Successful TPS
 *   3. Block-normalized TPS
 *   4. Transactions per block
 *   5. Successful transactions per block
 *   6. Block span
 *   7. Execution interval
 *
 * IMPORTANT:
 *
 * TPS is reported as an experimental observation.
 * It is NOT presented as an intrinsic maximum capability of
 * Ethereum unless the experiment explicitly saturates the network.
 */


/* ================================================================
                            TYPES
   ================================================================ */

interface ReceiptRecord {
    model: string;

    datasetRowId: number;

    blockchainTransactionId: string;

    transactionHash: string;

    blockNumber: number;

    receiptStatus: number;

    gasUsed: string;

    effectiveGasPriceWei: string;

    gasCostWei: string;

    contractAddress: string;

    submittedAtUnixMs: number;

    confirmedAtUnixMs: number;

    confirmationLatencyMs: number;

    participantAddress: string;

    validatorAddress: string;

    datasetHash: string;

    experimentId: string;
}


interface ThroughputStatistics {

    model: string;

    observations: number;

    successfulTransactions: number;

    failedTransactions: number;

    successRatePercent: number;

    executionIntervalMs: number;

    executionIntervalSeconds: number;

    attemptedTPS: number;

    successfulTPS: number;

    firstBlock: number;

    lastBlock: number;

    blockSpan: number;

    attemptedTransactionsPerBlock: number;

    successfulTransactionsPerBlock: number;

    successfulBlocks: number;

    blockNormalizedSuccessfulTPS: number;
}


/* ================================================================
                            PATHS
   ================================================================ */

const INPUT_FILE =
    path.join(
        process.cwd(),
        "results",
        "raw",
        "canonical_receipts.jsonl"
    );

const OUTPUT_DIRECTORY =
    path.join(
        process.cwd(),
        "results",
        "tables"
    );

const OUTPUT_JSON =
    path.join(
        OUTPUT_DIRECTORY,
        "throughput_statistics.json"
    );

const OUTPUT_CSV =
    path.join(
        OUTPUT_DIRECTORY,
        "throughput_statistics.csv"
    );


/* ================================================================
                        LOAD RECEIPTS
   ================================================================ */

function loadReceipts(): ReceiptRecord[] {

    if (
        !fs.existsSync(INPUT_FILE)
    ) {
        throw new Error(
            `Receipt file not found: ${INPUT_FILE}`
        );
    }

    const content =
        fs.readFileSync(
            INPUT_FILE,
            "utf8"
        ).trim();

    if (
        content.length === 0
    ) {
        throw new Error(
            "Receipt file is empty."
        );
    }

    return content
        .split(/\r?\n/)
        .filter(Boolean)
        .map(
            (line, index) => {

                try {

                    return JSON.parse(
                        line
                    ) as ReceiptRecord;

                } catch {

                    throw new Error(
                        `Invalid JSON at line ${index + 1}`
                    );
                }
            }
        );
}


/* ================================================================
                    VALIDATE RECEIPTS
   ================================================================ */

function validateRecords(
    records: ReceiptRecord[]
): void {

    if (
        records.length === 0
    ) {
        throw new Error(
            "No receipt observations available."
        );
    }

    for (
        const record of records
    ) {

        if (
            !record.model
        ) {
            throw new Error(
                "Receipt record has no model."
            );
        }

        if (
            !Number.isFinite(
                record.blockNumber
            )
        ) {
            throw new Error(
                `Invalid block number: ${record.transactionHash}`
            );
        }

        if (
            !Number.isFinite(
                record.submittedAtUnixMs
            )
        ) {
            throw new Error(
                `Invalid submission timestamp: ${record.transactionHash}`
            );
        }

        if (
            !Number.isFinite(
                record.confirmedAtUnixMs
            )
        ) {
            throw new Error(
                `Invalid confirmation timestamp: ${record.transactionHash}`
            );
        }

        if (
            record.confirmedAtUnixMs <
            record.submittedAtUnixMs
        ) {
            throw new Error(
                `Negative execution interval: ${record.transactionHash}`
            );
        }

        if (
            record.receiptStatus !== 0 &&
            record.receiptStatus !== 1
        ) {
            throw new Error(
                `Invalid receipt status: ${record.transactionHash}`
            );
        }
    }
}


/* ================================================================
                    UNIQUE BLOCK COUNT
   ================================================================ */

function uniqueBlocks(
    records: ReceiptRecord[]
): number[] {

    return [
        ...new Set(
            records.map(
                record =>
                    record.blockNumber
            )
        )
    ].sort(
        (a, b) =>
            a - b
    );
}


/* ================================================================
                    MODEL ANALYSIS
   ================================================================ */

function analyseModel(
    model: string,
    records: ReceiptRecord[]
): ThroughputStatistics {

    const modelRecords =
        records.filter(
            record =>
                record.model === model
        );

    if (
        modelRecords.length === 0
    ) {
        throw new Error(
            `No observations found for model: ${model}`
        );
    }


    /*
     * ------------------------------------------------------------
     * Sort observations by confirmation time.
     * ------------------------------------------------------------
     */

    const sorted =
        [...modelRecords].sort(
            (
                a,
                b
            ) =>
                a.confirmedAtUnixMs -
                b.confirmedAtUnixMs
        );


    const firstTimestamp =
        sorted[0]
            .confirmedAtUnixMs;

    const lastTimestamp =
        sorted[
            sorted.length - 1
        ]
            .confirmedAtUnixMs;


    /*
     * If every transaction is confirmed inside the same
     * millisecond, avoid division by zero.
     */
    const executionIntervalMs =
        Math.max(
            1,
            lastTimestamp -
            firstTimestamp
        );


    const executionIntervalSeconds =
        executionIntervalMs /
        1_000;


    const successful =
        modelRecords.filter(
            record =>
                record.receiptStatus === 1
        );


    const failed =
        modelRecords.filter(
            record =>
                record.receiptStatus === 0
        );


    /*
     * ------------------------------------------------------------
     * Transaction throughput
     * ------------------------------------------------------------
     */

    const attemptedTPS =
        modelRecords.length /
        executionIntervalSeconds;


    const successfulTPS =
        successful.length /
        executionIntervalSeconds;


    /*
     * ------------------------------------------------------------
     * Block analysis
     * ------------------------------------------------------------
     */

    const blocks =
        uniqueBlocks(
            modelRecords
        );


    const firstBlock =
        blocks[0];

    const lastBlock =
        blocks[
            blocks.length - 1
        ];


    /*
     * Number of block transitions.
     *
     * Example:
     *
     * firstBlock = 100
     * lastBlock  = 104
     *
     * blockSpan = 4
     */
    const blockSpan =
        Math.max(
            0,
            lastBlock -
            firstBlock
        );


    const attemptedTransactionsPerBlock =
        modelRecords.length /
        blocks.length;


    const successfulTransactionsPerBlock =
        successful.length /
        blocks.length;


    /*
     * ------------------------------------------------------------
     * Block-normalized throughput
     * ------------------------------------------------------------
     *
     * This is only meaningful if the benchmark records block
     * production/arrival time consistently.
     *
     * For local Hardhat auto-mining, this should NOT be treated
     * as a network consensus throughput measurement.
     *
     * Therefore this metric is labelled explicitly as
     * block-normalized experimental throughput.
     */
    const blockNormalizedSuccessfulTPS =
        blockSpan > 0
            ? successful.length /
              blockSpan
            : 0;


    return {

        model,

        observations:
            modelRecords.length,

        successfulTransactions:
            successful.length,

        failedTransactions:
            failed.length,

        successRatePercent:
            (
                successful.length /
                modelRecords.length
            ) *
            100,

        executionIntervalMs,

        executionIntervalSeconds,

        attemptedTPS,

        successfulTPS,

        firstBlock,

        lastBlock,

        blockSpan,

        attemptedTransactionsPerBlock,

        successfulTransactionsPerBlock,

        successfulBlocks:
            blocks.length,

        blockNormalizedSuccessfulTPS
    };
}


/* ================================================================
                        CSV OUTPUT
   ================================================================ */

function writeCSV(
    statistics: ThroughputStatistics[]
): void {

    const header = [
        "model",
        "observations",
        "successfulTransactions",
        "failedTransactions",
        "successRatePercent",
        "executionIntervalMs",
        "executionIntervalSeconds",
        "attemptedTPS",
        "successfulTPS",
        "firstBlock",
        "lastBlock",
        "blockSpan",
        "attemptedTransactionsPerBlock",
        "successfulTransactionsPerBlock",
        "successfulBlocks",
        "blockNormalizedSuccessfulTPS"
    ];


    const rows =
        statistics.map(
            stat =>
                [
                    stat.model,
                    stat.observations,
                    stat.successfulTransactions,
                    stat.failedTransactions,
                    stat.successRatePercent.toFixed(6),
                    stat.executionIntervalMs,
                    stat.executionIntervalSeconds.toFixed(6),
                    stat.attemptedTPS.toFixed(6),
                    stat.successfulTPS.toFixed(6),
                    stat.firstBlock,
                    stat.lastBlock,
                    stat.blockSpan,
                    stat.attemptedTransactionsPerBlock.toFixed(6),
                    stat.successfulTransactionsPerBlock.toFixed(6),
                    stat.successfulBlocks,
                    stat.blockNormalizedSuccessfulTPS.toFixed(6)
                ].join(",")
        );


    fs.writeFileSync(
        OUTPUT_CSV,
        [
            header.join(","),
            ...rows
        ].join("\n")
    );
}


/* ================================================================
                            MAIN
   ================================================================ */

function main(): void {

    console.log(
        "\n=============================================="
    );

    console.log(
        " GreenTrustChain Throughput Analysis"
    );

    console.log(
        "==============================================\n"
    );


    const records =
        loadReceipts();

    validateRecords(
        records
    );


    console.log(
        `Receipt observations: ${records.length}`
    );


    /*
     * Discover models dynamically.
     */

    const models =
        [
            ...new Set(
                records.map(
                    record =>
                        record.model
                )
            )
        ];


    const statistics =
        models.map(
            model =>
                analyseModel(
                    model,
                    records
                )
        );


    /*
     * ------------------------------------------------------------
     * Save JSON
     * ------------------------------------------------------------
     */

    fs.mkdirSync(
        OUTPUT_DIRECTORY,
        {
            recursive: true
        }
    );


    fs.writeFileSync(
        OUTPUT_JSON,
        JSON.stringify(
            {
                generatedAt:
                    new Date().toISOString(),

                input:
                    INPUT_FILE,

                primaryDefinition:
                    "successfulTransactions / executionIntervalSeconds",

                unit:
                    "transactions per second",

                statistics
            },
            null,
            2
        )
    );


    /*
     * ------------------------------------------------------------
     * Save CSV
     * ------------------------------------------------------------
     */

    writeCSV(
        statistics
    );


    /*
     * ------------------------------------------------------------
     * Console summary
     * ------------------------------------------------------------ */

    console.log(
        "\nThroughput comparison:\n"
    );


    for (
        const stat of statistics
    ) {

        console.log(
            `${stat.model}`
        );

        console.log(
            `  Observations      : ${stat.observations}`
        );

        console.log(
            `  Successful        : ${stat.successfulTransactions}`
        );

        console.log(
            `  Success rate      : ` +
            `${stat.successRatePercent.toFixed(2)}%`
        );

        console.log(
            `  Interval          : ` +
            `${stat.executionIntervalSeconds.toFixed(3)} s`
        );

        console.log(
            `  Attempted TPS     : ` +
            `${stat.attemptedTPS.toFixed(3)}`
        );

        console.log(
            `  Successful TPS    : ` +
            `${stat.successfulTPS.toFixed(3)}`
        );

        console.log(
            `  First block       : ${stat.firstBlock}`
        );

        console.log(
            `  Last block        : ${stat.lastBlock}`
        );

        console.log(
            `  Block count       : ${stat.successfulBlocks}`
        );

        console.log(
            `  Tx/block          : ` +
            `${stat.attemptedTransactionsPerBlock.toFixed(3)}`
        );

        console.log("");
    }


    console.log(
        "Outputs:"
    );

    console.log(
        OUTPUT_JSON
    );

    console.log(
        OUTPUT_CSV
    );
}


main();