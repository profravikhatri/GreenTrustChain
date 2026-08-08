"""
GreenTrustChain
Dataset-to-Trust Model Adapter

Purpose
-------
Explicitly map validated dataset variables to the four trust
dimensions defined by the research model:

    H = Historical Reliability
    D = Data Consistency
    C = Communication Reliability
    X = Contextual Operational Trust

This module does NOT modify the raw dataset.

It creates an experiment-ready representation and records exactly
which dataset fields support each trust dimension.

IMPORTANT
---------
No missing research variable is fabricated.

If a required dimension is not supported by the dataset, the
adapter fails and reports the missing evidence.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


# ================================================================
# PATHS
# ================================================================

PROJECT_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_DATASET = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "GSCROF_benchmark_95556.csv"
)

DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results"
    / "trust"
    / "trust_model_input.csv"
)

DEFAULT_MAPPING_REPORT = (
    PROJECT_ROOT
    / "results"
    / "trust"
    / "trust_variable_mapping.json"
)


# ================================================================
# TRUST DIMENSIONS
# ================================================================

TRUST_DIMENSIONS = {
    "H": "historical_reliability",
    "D": "data_consistency",
    "C": "communication_reliability",
    "X": "contextual_trust",
}


# ================================================================
# EXPLICIT VARIABLE CANDIDATES
# ================================================================
#
# These are candidate names only.
#
# The adapter selects a variable ONLY if it actually exists in
# the supplied dataset.
#
# Do not silently rename an unrelated variable.
# ================================================================

VARIABLE_CANDIDATES = {

    "H": [
        "historical_reliability",
        "historical_trust",
        "trust_score",
    ],

    "D": [
        "data_consistency",
        "consistency_score",
    ],

    "C": [
        "communication_reliability",
        "communication_success",
        "packet_delivery_ratio",
    ],

    "X": [
        "contextual_trust",
        "operational_trust",
        "context_score",
    ],
}


# ================================================================
# DATASET LOADER
# ================================================================

def load_dataset(
    dataset_path: Path,
) -> pd.DataFrame:

    if not dataset_path.exists():

        raise FileNotFoundError(
            f"Dataset not found:\n{dataset_path}"
        )

    dataframe = pd.read_csv(
        dataset_path
    )

    if dataframe.empty:

        raise ValueError(
            "Dataset contains zero records."
        )

    return dataframe


# ================================================================
# VARIABLE RESOLUTION
# ================================================================

def resolve_variable(
    dataframe: pd.DataFrame,
    dimension: str,
) -> str | None:
    """
    Resolve a trust variable only from columns that actually
    exist in the dataset.
    """

    candidates =
        VARIABLE_CANDIDATES[
            dimension
        ]

    for candidate in candidates:

        if candidate in dataframe.columns:

            return candidate

    return None


# ================================================================
# MAPPING AUDIT
# ================================================================

def build_mapping(
    dataframe: pd.DataFrame,
) -> dict:

    mapping = {}

    for dimension, name in TRUST_DIMENSIONS.items():

        selected =
            resolve_variable(
                dataframe,
                dimension,
            )

        mapping[name] = {

            "dimension":
                dimension,

            "selected_column":
                selected,

            "supported":
                selected is not None,

            "candidate_columns":
                VARIABLE_CANDIDATES[
                    dimension
                ],
        }

    return mapping


# ================================================================
# REQUIRED RESEARCH EVIDENCE
# ================================================================

def validate_mapping(
    mapping: dict,
) -> None:

    missing = [
        name
        for name, information
        in mapping.items()
        if not information["supported"]
    ]

    if missing:

        message = [
            "",
            "TRUST MODEL DATA SUPPORT FAILURE",
            "=================================",
            "",
            "The dataset does not explicitly support:",
            "",
        ]

        for dimension in missing:

            message.append(
                f"- {dimension}"
            )

        message.extend(
            [
                "",
                "No synthetic variables have been created.",
                "",
                "Define an experimentally justified mapping "
                "or revise the model/dataset before continuing.",
            ]
        )

        raise ValueError(
            "\n".join(message)
        )


# ================================================================
# NUMERIC VALIDATION
# ================================================================

def validate_numeric_columns(
    dataframe: pd.DataFrame,
    mapping: dict,
) -> None:

    for name, information in mapping.items():

        column =
            information[
                "selected_column"
            ]

        if column is None:
            continue

        numeric =
            pd.to_numeric(
                dataframe[column],
                errors="coerce",
            )

        invalid =
            int(
                numeric.isna().sum()
            )

        if invalid > 0:

            raise ValueError(
                f"Variable '{column}' mapped to "
                f"'{name}' contains {invalid} "
                "non-numeric/missing values."
            )


# ================================================================
# RANGE INFORMATION
# ================================================================

def collect_ranges(
    dataframe: pd.DataFrame,
    mapping: dict,
) -> dict:

    result = {}

    for name, information in mapping.items():

        column =
            information[
                "selected_column"
            ]

        if column is None:

            result[name] = None

            continue

        values =
            pd.to_numeric(
                dataframe[column],
                errors="coerce",
            )

        result[name] = {

            "column":
                column,

            "minimum":
                float(values.min()),

            "maximum":
                float(values.max()),

            "mean":
                float(values.mean()),

            "median":
                float(values.median()),
        }

    return result


# ================================================================
# BUILD MODEL INPUT
# ================================================================

def build_model_input(
    dataframe: pd.DataFrame,
    mapping: dict,
) -> pd.DataFrame:
    """
    Create a separate experiment input table.

    The original dataset remains untouched.
    """

    required_identity = [
        "row_id",
        "prosumer_id",
        "feeder_id",
    ]

    missing_identity = [
        column
        for column in required_identity
        if column not in dataframe.columns
    ]

    if missing_identity:

        raise ValueError(
            "Required identity columns missing: "
            + ", ".join(missing_identity)
        )

    result =
        dataframe[
            required_identity
        ].copy()

    for name, information in mapping.items():

        source =
            information[
                "selected_column"
            ]

        result[
            name
        ] =
            pd.to_numeric(
                dataframe[source],
                errors="coerce",
            )

    return result


# ================================================================
# SAVE RESULTS
# ================================================================

def save_outputs(
    model_input: pd.DataFrame,
    mapping: dict,
    ranges: dict,
    dataset_path: Path,
) -> None:

    DEFAULT_OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    model_input.to_csv(
        DEFAULT_OUTPUT,
        index=False,
    )

    report = {

        "dataset": {
            "path":
                str(dataset_path),

            "records":
                int(len(model_input)),
        },

        "trust_dimensions": mapping,

        "observed_ranges":
            ranges,

        "output": {
            "model_input":
                str(DEFAULT_OUTPUT),

            "mapping_report":
                str(DEFAULT_MAPPING_REPORT),
        },

        "research_rule":
            (
                "Only explicitly present dataset variables are "
                "mapped. Missing trust dimensions are not "
                "synthetically generated."
            ),
    }

    with DEFAULT_MAPPING_REPORT.open(
        "w",
        encoding="utf-8",
    ) as file:

        json.dump(
            report,
            file,
            indent=2,
        )


# ================================================================
# MAIN
# ================================================================

def main():

    parser = argparse.ArgumentParser(
        description=(
            "Map the experimental dataset to the "
            "GreenTrustChain trust dimensions."
        )
    )

    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
    )

    args =
        parser.parse_args()

    print(
        "\nGreenTrustChain Dataset Adapter"
    )

    print(
        "================================\n"
    )

    dataframe =
        load_dataset(
            args.dataset
        )

    print(
        f"Records: {len(dataframe):,}"
    )

    print(
        f"Columns: {len(dataframe.columns)}\n"
    )

    mapping =
        build_mapping(
            dataframe
        )

    print(
        "Trust-variable mapping:"
    )

    for name, information in mapping.items():

        print(
            f"  {name}: "
            f"{information['selected_column']}"
        )

    validate_mapping(
        mapping
    )

    validate_numeric_columns(
        dataframe,
        mapping,
    )

    ranges =
        collect_ranges(
            dataframe,
            mapping,
        )

    model_input =
        build_model_input(
            dataframe,
            mapping,
        )

    save_outputs(
        model_input,
        mapping,
        ranges,
        args.dataset,
    )

    print(
        "\nMapping validation: PASS"
    )

    print(
        f"Model input: {DEFAULT_OUTPUT}"
    )

    print(
        f"Mapping report: {DEFAULT_MAPPING_REPORT}"
    )


if __name__ == "__main__":

    main()