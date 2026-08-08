"""
GreenTrustChain
Dataset Audit and Reproducibility Module

Purpose
-------
Validate the experimental energy-market dataset before blockchain replay.

The audit checks:

1. File existence
2. SHA-256 fingerprint
3. Row count
4. Column schema
5. Missing values
6. Duplicate records
7. Numeric validity
8. Unique prosumers
9. Unique feeders
10. Trust-score range
11. Basic statistical distribution
12. Dataset integrity

IMPORTANT
---------
This script DOES NOT modify the source dataset.

It creates an audit report that should be retained with
the blockchain experimental results.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd


# ================================================================
# PATH CONFIGURATION
# ================================================================

DEFAULT_DATASET = (
    Path(__file__).resolve().parents[1]
    / "data"
    / "raw"
    / "GSCROF_benchmark_95556.csv"
)

RESULT_DIR = (
    Path(__file__).resolve().parents[1]
    / "results"
    / "dataset_audit"
)


# ================================================================
# EXPECTED SCHEMA
# ================================================================

EXPECTED_COLUMNS = [
    "row_id",
    "prosumer_id",
    "feeder_id",
    "power_kw",
    "voltage_pu",
    "loss_index",
    "curtailment_index",
    "carbon_proxy",
    "trust_score",
]


NUMERIC_COLUMNS = [
    "row_id",
    "feeder_id",
    "power_kw",
    "voltage_pu",
    "loss_index",
    "curtailment_index",
    "carbon_proxy",
    "trust_score",
]


# ================================================================
# SHA-256
# ================================================================

def calculate_sha256(
    file_path: Path,
    chunk_size: int = 1024 * 1024,
) -> str:
    """
    Calculate SHA-256 without loading the complete file into memory.
    """

    digest = hashlib.sha256()

    with file_path.open("rb") as file:

        while True:

            chunk = file.read(chunk_size)

            if not chunk:
                break

            digest.update(chunk)

    return digest.hexdigest()


# ================================================================
# SAFE JSON CONVERSION
# ================================================================

def json_safe(value):
    """
    Convert NumPy/Pandas values into JSON-compatible values.
    """

    if isinstance(value, (np.integer,)):
        return int(value)

    if isinstance(value, (np.floating,)):
        return float(value)

    if isinstance(value, (np.bool_,)):
        return bool(value)

    if pd.isna(value):
        return None

    return value


# ================================================================
# SCHEMA AUDIT
# ================================================================

def audit_schema(
    dataframe: pd.DataFrame,
) -> dict:

    actual =
        list(dataframe.columns)

    missing_columns = [
        column
        for column in EXPECTED_COLUMNS
        if column not in actual
    ]

    unexpected_columns = [
        column
        for column in actual
        if column not in EXPECTED_COLUMNS
    ]

    column_order_matches = (
        actual == EXPECTED_COLUMNS
    )

    return {
        "expected_columns": EXPECTED_COLUMNS,
        "actual_columns": actual,
        "missing_columns": missing_columns,
        "unexpected_columns": unexpected_columns,
        "column_order_matches": column_order_matches,
        "schema_valid":
            len(missing_columns) == 0,
    }


# ================================================================
# MISSING-VALUE AUDIT
# ================================================================

def audit_missing_values(
    dataframe: pd.DataFrame,
) -> dict:

    missing_counts = (
        dataframe
        .isna()
        .sum()
        .to_dict()
    )

    total_missing = int(
        dataframe.isna().sum().sum()
    )

    return {
        "total_missing_cells": total_missing,
        "missing_by_column": {
            key: int(value)
            for key, value in missing_counts.items()
        },
        "has_missing_values":
            total_missing > 0,
    }


# ================================================================
# DUPLICATE AUDIT
# ================================================================

def audit_duplicates(
    dataframe: pd.DataFrame,
) -> dict:

    complete_duplicates = int(
        dataframe.duplicated(
            keep=False
        ).sum()
    )

    duplicate_rows = int(
        dataframe.duplicated(
            keep="first"
        ).sum()
    )

    if "row_id" in dataframe.columns:

        duplicate_row_ids = int(
            dataframe["row_id"]
            .duplicated(
                keep=False
            )
            .sum()
        )

    else:

        duplicate_row_ids = None

    return {
        "duplicate_complete_rows":
            complete_duplicates,

        "duplicate_rows_excluding_first":
            duplicate_rows,

        "duplicate_row_ids":
            duplicate_row_ids,

        "has_complete_duplicates":
            complete_duplicates > 0,

        "has_duplicate_row_ids":
            (
                duplicate_row_ids is not None
                and duplicate_row_ids > 0
            ),
    }


# ================================================================
# NUMERIC-TYPE AUDIT
# ================================================================

def audit_numeric_columns(
    dataframe: pd.DataFrame,
) -> dict:

    results = {}

    for column in NUMERIC_COLUMNS:

        if column not in dataframe.columns:

            results[column] = {
                "present": False,
                "numeric": False,
            }

            continue

        converted = pd.to_numeric(
            dataframe[column],
            errors="coerce",
        )

        invalid_count = int(
            converted.isna().sum()
        )

        results[column] = {
            "present": True,
            "numeric": invalid_count == 0,
            "invalid_values": invalid_count,
        }

    return results


# ================================================================
# VALUE-RANGE AUDIT
# ================================================================

def audit_ranges(
    dataframe: pd.DataFrame,
) -> dict:

    results = {}

    def add_range(
        column: str,
        minimum=None,
        maximum=None,
    ):

        if column not in dataframe.columns:

            results[column] = {
                "available": False,
            }

            return

        values = pd.to_numeric(
            dataframe[column],
            errors="coerce",
        )

        result = {
            "available": True,
            "minimum": (
                float(values.min())
                if not values.dropna().empty
                else None
            ),
            "maximum": (
                float(values.max())
                if not values.dropna().empty
                else None
            ),
        }

        if minimum is not None:

            result["expected_minimum"] = minimum

            result["below_minimum"] = int(
                (values < minimum).sum()
            )

        if maximum is not None:

            result["expected_maximum"] = maximum

            result["above_maximum"] = int(
                (values > maximum).sum()
            )

        results[column] = result

    /*
     * Trust is represented internally on the
     * proposed fixed-point scale [0, 10000].
     */

    add_range(
        "trust_score",
        minimum=0,
        maximum=10000,
    )

    /*
     * Physical/operational ranges are deliberately
     * NOT invented here. They must be established from
     * the actual dataset specification.
     */

    for column in [
        "power_kw",
        "voltage_pu",
        "loss_index",
        "curtailment_index",
        "carbon_proxy",
    ]:

        add_range(column)

    return results


# ================================================================
# STATISTICAL SUMMARY
# ================================================================

def audit_statistics(
    dataframe: pd.DataFrame,
) -> dict:

    available_columns = [
        column
        for column in NUMERIC_COLUMNS
        if column in dataframe.columns
    ]

    statistics = {}

    for column in available_columns:

        numeric =
            pd.to_numeric(
                dataframe[column],
                errors="coerce",
            )

        clean =
            numeric.dropna()

        if clean.empty:

            continue

        statistics[column] = {
            "count": int(clean.count()),
            "mean": float(clean.mean()),
            "std": float(clean.std()),
            "min": float(clean.min()),
            "p25": float(clean.quantile(0.25)),
            "median": float(clean.median()),
            "p75": float(clean.quantile(0.75)),
            "p95": float(clean.quantile(0.95)),
            "p99": float(clean.quantile(0.99)),
            "max": float(clean.max()),
        }

    return statistics


# ================================================================
# ENTITY AUDIT
# ================================================================

def audit_entities(
    dataframe: pd.DataFrame,
) -> dict:

    result = {}

    if "prosumer_id" in dataframe.columns:

        result["unique_prosumers"] = int(
            dataframe[
                "prosumer_id"
            ].nunique()
        )

    else:

        result["unique_prosumers"] = None

    if "feeder_id" in dataframe.columns:

        result["unique_feeders"] = int(
            dataframe[
                "feeder_id"
            ].nunique()
        )

    else:

        result["unique_feeders"] = None

    return result


# ================================================================
# ROW-ID AUDIT
# ================================================================

def audit_row_ids(
    dataframe: pd.DataFrame,
) -> dict:

    if "row_id" not in dataframe.columns:

        return {
            "available": False,
        }

    row_ids =
        pd.to_numeric(
            dataframe["row_id"],
            errors="coerce",
        )

    clean =
        row_ids.dropna()

    if clean.empty:

        return {
            "available": True,
            "valid": False,
        }

    expected_sequence =
        np.arange(
            len(clean)
        )

    sorted_ids =
        np.sort(
            clean.to_numpy()
        )

    zero_based_sequence =
        np.arange(
            int(sorted_ids.min()),
            int(sorted_ids.max()) + 1,
        )

    return {
        "available": True,

        "valid_numeric":
            len(clean) == len(row_ids),

        "minimum":
            int(sorted_ids.min()),

        "maximum":
            int(sorted_ids.max()),

        "unique":
            int(clean.nunique()),

        "expected_rows":
            len(dataframe),

        "sequence_contiguous":
            np.array_equal(
                sorted_ids,
                zero_based_sequence,
            ),
    }


# ================================================================
# MAIN AUDIT
# ================================================================

def run_audit(
    dataset_path: Path,
) -> dict:

    if not dataset_path.exists():

        raise FileNotFoundError(
            f"Dataset not found: {dataset_path}"
        )

    print(
        f"Reading dataset:\n{dataset_path}\n"
    )

    dataframe = pd.read_csv(
        dataset_path
    )

    print(
        f"Rows: {len(dataframe):,}"
    )

    print(
        f"Columns: {len(dataframe.columns)}"
    )

    print(
        "Calculating SHA-256..."
    )

    dataset_hash =
        calculate_sha256(
            dataset_path
        )

    print(
        f"SHA-256: {dataset_hash}"
    )

    schema =
        audit_schema(
            dataframe
        )

    missing =
        audit_missing_values(
            dataframe
        )

    duplicates =
        audit_duplicates(
            dataframe
        )

    numeric =
        audit_numeric_columns(
            dataframe
        )

    ranges =
        audit_ranges(
            dataframe
        )

    statistics =
        audit_statistics(
            dataframe
        )

    entities =
        audit_entities(
            dataframe
        )

    row_ids =
        audit_row_ids(
            dataframe
        )

    /*
     * ------------------------------------------------------------
     * Overall integrity status
     * ------------------------------------------------------------
     *
     * We do not silently repair the data.
     */

    numeric_valid =
        all(
            item.get(
                "numeric",
                False
            )
            for item in numeric.values()
            if item.get("present", False)
        )

    integrity_pass =
        (
            schema["schema_valid"]
            and not missing["has_missing_values"]
            and not duplicates["has_complete_duplicates"]
            and numeric_valid
        )

    report = {

        "audit_metadata": {

            "audit_timestamp_utc":
                datetime.now(
                    timezone.utc
                ).isoformat(),

            "dataset_path":
                str(dataset_path),

            "dataset_filename":
                dataset_path.name,

            "sha256":
                dataset_hash,

            "pandas_version":
                pd.__version__,

            "python_version":
                sys.version,

        },

        "dataset_dimensions": {

            "rows":
                int(len(dataframe)),

            "columns":
                int(len(dataframe.columns)),
        },

        "integrity": {

            "audit_pass":
                bool(integrity_pass),

            "note":
                (
                    "Audit reports detected conditions; "
                    "it does not modify or repair the dataset."
                ),
        },

        "schema":
            schema,

        "missing_values":
            missing,

        "duplicates":
            duplicates,

        "numeric_validation":
            numeric,

        "value_ranges":
            ranges,

        "statistics":
            statistics,

        "entities":
            entities,

        "row_id":
            row_ids,
    }

    return report


# ================================================================
# SAVE REPORT
# ================================================================

def save_report(
    report: dict,
) -> None:

    RESULT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    json_path =
        RESULT_DIR /
        "dataset_audit.json"

    txt_path =
        RESULT_DIR /
        "dataset_audit_summary.txt"

    with json_path.open(
        "w",
        encoding="utf-8",
    ) as file:

        json.dump(
            report,
            file,
            indent=2,
            ensure_ascii=False,
        )


    integrity =
        report[
            "integrity"
        ]["audit_pass"]

    summary = []

    summary.append(
        "GreenTrustChain Dataset Audit"
    )

    summary.append(
        "=" * 50
    )

    summary.append(
        f"Audit status: "
        f"{'PASS' if integrity else 'REVIEW REQUIRED'}"
    )

    summary.append(
        f"Rows: "
        f"{report['dataset_dimensions']['rows']:,}"
    )

    summary.append(
        f"Columns: "
        f"{report['dataset_dimensions']['columns']}"
    )

    summary.append(
        f"SHA-256: "
        f"{report['audit_metadata']['sha256']}"
    )

    summary.append(
        ""
    )

    summary.append(
        f"Unique prosumers: "
        f"{report['entities'].get('unique_prosumers')}"
    )

    summary.append(
        f"Unique feeders: "
        f"{report['entities'].get('unique_feeders')}"
    )

    summary.append(
        f"Missing cells: "
        f"{report['missing_values']['total_missing_cells']}"
    )

    summary.append(
        f"Duplicate complete rows: "
        f"{report['duplicates']['duplicate_complete_rows']}"
    )

    summary.append(
        ""
    )

    summary.append(
        "This report is observational and does not "
        "modify the source dataset."
    )

    txt_path.write_text(
        "\n".join(summary),
        encoding="utf-8",
    )

    print(
        f"\nAudit JSON:\n{json_path}"
    )

    print(
        f"Audit summary:\n{txt_path}"
    )


# ================================================================
# CLI
# ================================================================

def parse_arguments():

    parser = argparse.ArgumentParser(
        description=(
            "Audit the GreenTrustChain "
            "experimental dataset."
        )
    )

    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
        help=(
            "Path to the CSV dataset."
        ),
    )

    return parser.parse_args()


# ================================================================
# ENTRY POINT
# ================================================================

def main():

    args =
        parse_arguments()

    try:

        report =
            run_audit(
                args.dataset
            )

        save_report(
            report
        )

        if (
            report["integrity"]["audit_pass"]
        ):

            print(
                "\nDATASET AUDIT: PASS"
            )

        else:

            print(
                "\nDATASET AUDIT: REVIEW REQUIRED"
            )

    except Exception as error:

        print(
            "\nDATASET AUDIT FAILED"
        )

        print(
            str(error)
        )

        sys.exit(1)


if __name__ == "__main__":
    main()