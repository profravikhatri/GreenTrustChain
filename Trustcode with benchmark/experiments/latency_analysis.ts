import fs from "fs";
import path from "path";

/**
 * GreenTrustChain
 * Latency Analysis
 *
 * Purpose:
 *   Analyse blockchain confirmation latency from the canonical
 *   receipt dataset.
 *
 * This script DOES NOT interact with the blockchain.
 *
 * It consumes:
 *
 *   results/raw/canonical_receipts.jsonl
 *
 * and produces reproducible latency statistics.
 *
 * Latency definition used here:
 *
 *   confirmationLatencyMs =
 *       confirmedAtUnixMs - submittedAtUnixMs
 *
 * This represents the observed wall-clock confirmation interval
 * recorded by the experiment runner.
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


interface LatencyStatistics {
    model: string;

    observations: number;

    successfulTransactions: number;

    failedTransactions: number;

    successRatePercent: number;

    meanLatencyMs: number;

    medianLatencyMs: number;

    standardDeviationMs: number;

    minimumLatencyMs: number;

    maximumLatencyMs: number;

    p25LatencyMs: number;

    p75LatencyMs: number;

    p95LatencyMs: number;

    p99LatencyMs: number;

    meanSuccessfulLatencyMs: number;

    medianSuccessfulLatencyMs: number;
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
        "latency_statistics.json"
    );

const OUTPUT_CSV =
    path.join(
        OUTPUT_DIRECTORY,
        "latency_statistics.csv"
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
                    VALIDATE LATENCY DATA
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
                "Receipt record contains no model."
            );
        }

        if (
            !Number.isFinite(
                record.submittedAtUnixMs
            )
        ) {

            throw new Error(
                `Invalid submission time: ${record.transactionHash}`
            );
        }

        if (
            !Number.isFinite(
                record.confirmedAtUnixMs
            )
        ) {

            throw new Error(
                `Invalid confirmation time: ${record.transactionHash}`
            );
        }

        if (
            record.confirmedAtUnixMs <
            record.submittedAtUnixMs
        ) {

            throw new Error(
                `Negative timestamp interval: ${record.transactionHash}`
            );
        }

        if (
            !Number.isFinite(
                record.confirmationLatencyMs
            )
        ) {

            throw new Error(
                `Invalid latency: ${record.transactionHash}`
            );
        }

        if (
            record.confirmationLatencyMs < 0
        ) {

            throw new Error(
                `Negative latency: ${record.transactionHash}`
            );
        }
    }
}


/* ================================================================
                            MEAN
   ================================================================ */

function mean(
    values: number[]
): number {

    if (
        values.length === 0
    ) {

        return 0;
    }

    return (
        values.reduce(
            (sum, value) =>
                sum + value,
            0
        ) /
        values.length
    );
}


/* ================================================================
                            MEDIAN
   ================================================================ */

function median(
    values: number[]
): number {

    if (
        values.length === 0
    ) {

        return 0;
    }

    const sorted =
        [...values].sort(
            (a, b) =>
                a - b
        );

    const middle =
        Math.floor(
            sorted.length / 2
        );

    if (
        sorted.length % 2 === 0
    ) {

        return (
            sorted[middle - 1] +
            sorted[middle]
        ) / 2;
    }

    return sorted[middle];
}


/* ================================================================
                    STANDARD DEVIATION
   ================================================================ */

function standardDeviation(
    values: number[]
): number {

    if (
        values.length <= 1
    ) {

        return 0;
    }

    const average =
        mean(values);

    const squaredDifferences =
        values.map(
            value => {

                const difference =
                    value - average;

                return (
                    difference *
                    difference
                );
            }
        );

    const variance =
        squaredDifferences.reduce(
            (
                sum,
                value
            ) =>
                sum + value,
            0
        ) /
        (
            values.length - 1
        );

    return Math.sqrt(
        variance
    );
}


/* ================================================================
                        PERCENTILE
   ================================================================ */

function percentile(
    values: number[],
    percentileValue: number
): number {

    if (
        values.length === 0
    ) {

        return 0;
    }

    const sorted =
        [...values].sort(
            (a, b) =>
                a - b
        );

    if (
        percentileValue <= 0
    ) {

        return sorted[0];
    }

    if (
        percentileValue >= 100
    ) {

        return sorted[
            sorted.length - 1
        ];
    }

    const position =
        (
            percentileValue / 100
        ) *
        (
            sorted.length - 1
        );

    const lower =
        Math.floor(position);

    const upper =
        Math.ceil(position);

    if (
        lower === upper
    ) {

        return sorted[lower];
    }

    const weight =
        position - lower;

    return (
        sorted[lower] *
        (1 - weight)
    ) +
        (
            sorted[upper] *
            weight
        );
}


/* ================================================================
                    ANALYSE ONE MODEL
   ================================================================ */

function analyseModel(
    model: string,
    records: ReceiptRecord[]
): LatencyStatistics {

    const modelRecords =
        records.filter(
            record =>
                record.model === model
        );

    if (
        modelRecords.length === 0
    ) {

        throw new Error(
            `No records found for model: ${model}`
        );
    }


    /*
     * All observations.
     */
    const allLatencies =
        modelRecords.map(
            record =>
                record.confirmationLatencyMs
        );


    /*
     * Successful observations only.
     */
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

    const successfulLatencies =
        successful.map(
            record =>
                record.confirmationLatencyMs
        );


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

        meanLatencyMs:
            mean(
                allLatencies
            ),

        medianLatencyMs:
            median(
                allLatencies
            ),

        standardDeviationMs:
            standardDeviation(
                allLatencies
            ),

        minimumLatencyMs:
            Math.min(
                ...allLatencies
            ),

        maximumLatencyMs:
            Math.max(
                ...allLatencies
            ),

        p25LatencyMs:
            percentile(
                allLatencies,
                25
            ),

        p75LatencyMs:
            percentile(
                allLatencies,
                75
            ),

        p95LatencyMs:
            percentile(
                allLatencies,
                95
            ),

        p99LatencyMs:
            percentile(
                allLatencies,
                99
            ),

        meanSuccessfulLatencyMs:
            mean(
                successfulLatencies
            ),

        medianSuccessfulLatencyMs:
            median(
                successfulLatencies
            )
    };
}


/* ================================================================
                    LATENCY REDUCTION
   ================================================================ */

function latencyReductionPercent(
    baselineMean: number,
    proposedMean: number
): number {

    if (
        baselineMean === 0
    ) {

        return 0;
    }

    return (
        (
            baselineMean -
            proposedMean
        ) /
        baselineMean
    ) *
    100;
}


/* ================================================================
                        CSV OUTPUT
   ================================================================ */

function writeCSV(
    statistics: LatencyStatistics[]
): void {

    const header = [
        "model",
        "observations",
        "successfulTransactions",
        "failedTransactions",
        "successRatePercent",
        "meanLatencyMs",
        "medianLatencyMs",
        "standardDeviationMs",
        "minimumLatencyMs",
        "maximumLatencyMs",
        "p25LatencyMs",
        "p75LatencyMs",
        "p95LatencyMs",
        "p99LatencyMs",
        "meanSuccessfulLatencyMs",
        "medianSuccessfulLatencyMs"
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
                    stat.meanLatencyMs.toFixed(6),
                    stat.medianLatencyMs.toFixed(6),
                    stat.standardDeviationMs.toFixed(6),
                    stat.minimumLatencyMs.toFixed(6),
                    stat.maximumLatencyMs.toFixed(6),
                    stat.p25LatencyMs.toFixed(6),
                    stat.p75LatencyMs.toFixed(6),
                    stat.p95LatencyMs.toFixed(6),
                    stat.p99LatencyMs.toFixed(6),
                    stat.meanSuccessfulLatencyMs.toFixed(6),
                    stat.medianSuccessfulLatencyMs.toFixed(6)
                ]
                    .join(",")
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
        " GreenTrustChain Latency Analysis"
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
     * Discover all models represented in the
     * canonical experiment dataset.
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

                latencyDefinition:
                    "confirmedAtUnixMs - submittedAtUnixMs",

                unit:
                    "milliseconds",

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
     * ------------------------------------------------------------
     */

    console.log(
        "\nLatency comparison:\n"
    );


    for (
        const stat of statistics
    ) {

        console.log(
            `${stat.model}`
        );

        console.log(
            `  Observations : ${stat.observations}`
        );

        console.log(
            `  Success      : ` +
            `${stat.successRatePercent.toFixed(2)}%`
        );

        console.log(
            `  Mean         : ` +
            `${stat.meanLatencyMs.toFixed(2)} ms`
        );

        console.log(
            `  Median       : ` +
            `${stat.medianLatencyMs.toFixed(2)} ms`
        );

        console.log(
            `  P95          : ` +
            `${stat.p95LatencyMs.toFixed(2)} ms`
        );

        console.log(
            `  P99          : ` +
            `${stat.p99LatencyMs.toFixed(2)} ms`
        );

        console.log("");
    }


    /*
     * ------------------------------------------------------------
     * GreenTrustChain comparison
     * ------------------------------------------------------------
     */

    const greenTrust =
        statistics.find(
            stat =>
                stat.model ===
                "greentrustchain"
        );


    if (
        greenTrust
    ) {

        console.log(
            "GreenTrustChain latency comparison:\n"
        );


        for (
            const baseline of statistics
        ) {

            if (
                baseline.model ===
                "greentrustchain"
            ) {

                continue;
            }


            const reduction =
                latencyReductionPercent(
                    baseline.meanLatencyMs,
                    greenTrust.meanLatencyMs
                );


            console.log(
                `  vs ${baseline.model}: ` +
                `${reduction.toFixed(2)}%`
            );
        }
    }


    console.log(
        "\nOutputs:"
    );

    console.log(
        OUTPUT_JSON
    );

    console.log(
        OUTPUT_CSV
    );
}


main();