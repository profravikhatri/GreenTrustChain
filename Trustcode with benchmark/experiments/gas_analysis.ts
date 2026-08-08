import fs from "fs";
import path from "path";

/**
 * GreenTrustChain
 * Gas Consumption Analysis
 *
 * Purpose:
 *   Analyse canonical EVM transaction receipts.
 *
 * IMPORTANT:
 *   This script does NOT execute blockchain transactions.
 *   It only analyses previously collected observations.
 *
 * Outputs:
 *   - mean gas
 *   - median gas
 *   - standard deviation
 *   - minimum
 *   - maximum
 *   - P25
 *   - P75
 *   - P95
 *   - P99
 *   - successful transactions
 *   - failed transactions
 *   - gas per successful transaction
 *   - total gas
 *   - total gas cost
 *
 * Gas is reported as blockchain computational cost.
 * It is NOT interpreted directly as physical energy consumption.
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


interface ModelGasStatistics {
    model: string;

    observations: number;

    successfulTransactions: number;

    failedTransactions: number;

    successRatePercent: number;

    totalGasUsed: string;

    meanGasUsed: number;

    medianGasUsed: number;

    standardDeviationGas: number;

    minimumGasUsed: number;

    maximumGasUsed: number;

    p25GasUsed: number;

    p75GasUsed: number;

    p95GasUsed: number;

    p99GasUsed: number;

    meanGasCostWei: string;

    totalGasCostWei: string;
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
        "gas_statistics.json"
    );

const OUTPUT_CSV =
    path.join(
        OUTPUT_DIRECTORY,
        "gas_statistics.csv"
    );


/* ================================================================
                        FILE LOADING
   ================================================================ */

function loadReceipts(): ReceiptRecord[] {

    if (!fs.existsSync(INPUT_FILE)) {

        throw new Error(
            `Receipt file not found: ${INPUT_FILE}`
        );
    }

    const content =
        fs.readFileSync(
            INPUT_FILE,
            "utf8"
        ).trim();

    if (!content) {

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
                    NUMERICAL VALIDATION
   ================================================================ */

function validateReceipts(
    records: ReceiptRecord[]
): void {

    if (
        records.length === 0
    ) {

        throw new Error(
            "No receipt records available."
        );
    }

    for (
        const record of records
    ) {

        if (
            !record.model
        ) {
            throw new Error(
                "Receipt contains missing model."
            );
        }

        if (
            !Number.isFinite(
                Number(record.gasUsed)
            )
        ) {
            throw new Error(
                `Invalid gas value for ${record.transactionHash}`
            );
        }

        if (
            Number(record.gasUsed) < 0
        ) {
            throw new Error(
                `Negative gas value for ${record.transactionHash}`
            );
        }

        if (
            !Number.isFinite(
                record.confirmationLatencyMs
            )
        ) {
            throw new Error(
                `Invalid latency for ${record.transactionHash}`
            );
        }

        if (
            record.receiptStatus !== 0 &&
            record.receiptStatus !== 1
        ) {
            throw new Error(
                `Invalid receipt status for ${record.transactionHash}`
            );
        }
    }
}


/* ================================================================
                        SORTING
   ================================================================ */

function sortedValues(
    values: number[]
): number[] {

    return [...values].sort(
        (a, b) => a - b
    );
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
        ) / values.length
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
        sortedValues(values);

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

    const variance =
        values.reduce(
            (sum, value) => {

                const difference =
                    value - average;

                return (
                    sum +
                    difference *
                    difference
                );
            },
            0
        ) / (
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
        sortedValues(values);

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
                    BIGINT SUMMATION
   ================================================================ */

function sumBigInt(
    values: string[]
): bigint {

    return values.reduce(
        (
            total,
            value
        ) =>
            total +
            BigInt(value),
        0n
    );
}


/* ================================================================
                    MODEL ANALYSIS
   ================================================================ */

function analyseModel(
    model: string,
    records: ReceiptRecord[]
): ModelGasStatistics {

    const modelRecords =
        records.filter(
            record =>
                record.model === model
        );

    if (
        modelRecords.length === 0
    ) {

        throw new Error(
            `No records available for model: ${model}`
        );
    }

    const gasValues =
        modelRecords.map(
            record =>
                Number(
                    record.gasUsed
                )
        );

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

    const gasCosts =
        modelRecords.map(
            record =>
                record.gasCostWei
        );

    const totalGas =
        sumBigInt(
            modelRecords.map(
                record =>
                    record.gasUsed
            )
        );

    const totalGasCost =
        sumBigInt(
            gasCosts
        );

    const meanGasCost =
        modelRecords.length === 0
            ? 0n
            : totalGasCost /
              BigInt(
                  modelRecords.length
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

        totalGasUsed:
            totalGas.toString(),

        meanGasUsed:
            mean(gasValues),

        medianGasUsed:
            median(gasValues),

        standardDeviationGas:
            standardDeviation(
                gasValues
            ),

        minimumGasUsed:
            Math.min(
                ...gasValues
            ),

        maximumGasUsed:
            Math.max(
                ...gasValues
            ),

        p25GasUsed:
            percentile(
                gasValues,
                25
            ),

        p75GasUsed:
            percentile(
                gasValues,
                75
            ),

        p95GasUsed:
            percentile(
                gasValues,
                95
            ),

        p99GasUsed:
            percentile(
                gasValues,
                99
            ),

        meanGasCostWei:
            meanGasCost.toString(),

        totalGasCostWei:
            totalGasCost.toString()
    };
}


/* ================================================================
                    RELATIVE IMPROVEMENT
   ================================================================ */

function gasReductionPercent(
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
                        CSV WRITER
   ================================================================ */

function writeCSV(
    statistics: ModelGasStatistics[]
): void {

    const header = [
        "model",
        "observations",
        "successfulTransactions",
        "failedTransactions",
        "successRatePercent",
        "totalGasUsed",
        "meanGasUsed",
        "medianGasUsed",
        "standardDeviationGas",
        "minimumGasUsed",
        "maximumGasUsed",
        "p25GasUsed",
        "p75GasUsed",
        "p95GasUsed",
        "p99GasUsed",
        "meanGasCostWei",
        "totalGasCostWei"
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
                    stat.totalGasUsed,
                    stat.meanGasUsed.toFixed(6),
                    stat.medianGasUsed.toFixed(6),
                    stat.standardDeviationGas.toFixed(6),
                    stat.minimumGasUsed,
                    stat.maximumGasUsed,
                    stat.p25GasUsed.toFixed(6),
                    stat.p75GasUsed.toFixed(6),
                    stat.p95GasUsed.toFixed(6),
                    stat.p99GasUsed.toFixed(6),
                    stat.meanGasCostWei,
                    stat.totalGasCostWei
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
                    MAIN ANALYSIS
   ================================================================ */

function main(): void {

    console.log(
        "\n=============================================="
    );

    console.log(
        " GreenTrustChain Gas Analysis"
    );

    console.log(
        "==============================================\n"
    );


    const records =
        loadReceipts();

    validateReceipts(
        records
    );

    console.log(
        `Receipt observations: ${records.length}`
    );


    /*
     * ------------------------------------------------------------
     * Discover models dynamically
     * ------------------------------------------------------------
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
     * Save complete statistics
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

                observations:
                    records.length,

                statistics
            },
            null,
            2
        )
    );


    writeCSV(
        statistics
    );


    /*
     * ------------------------------------------------------------
     * Console summary
     * ------------------------------------------------------------
     */

    console.log(
        "\nModel comparison:\n"
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
            `  Success      : ${stat.successRatePercent.toFixed(2)}%`
        );

        console.log(
            `  Mean gas     : ${stat.meanGasUsed.toFixed(2)}`
        );

        console.log(
            `  Median gas   : ${stat.medianGasUsed.toFixed(2)}`
        );

        console.log(
            `  P95 gas      : ${stat.p95GasUsed.toFixed(2)}`
        );

        console.log(
            `  P99 gas      : ${stat.p99GasUsed.toFixed(2)}`
        );

        console.log(
            `  Total gas    : ${stat.totalGasUsed}`
        );

        console.log("");
    }


    /*
     * ------------------------------------------------------------
     * Relative comparison
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
            "GreenTrustChain relative gas reduction:\n"
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
                gasReductionPercent(
                    baseline.meanGasUsed,
                    greenTrust.meanGasUsed
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