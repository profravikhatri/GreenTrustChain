"""
GreenTrustChain
Multidimensional Trust Engine

Purpose
-------
Compute the off-chain multidimensional trust evidence used by
the GreenTrustChain experimental framework.

Trust dimensions:

    1. Historical Reliability
    2. Data Consistency
    3. Communication Reliability
    4. Contextual Operational Trust

Output:

    Continuous trust score in [0, 10000]

    0      -> minimum trust
    10000  -> maximum trust

IMPORTANT
---------
This module does NOT write to Ethereum.

It produces a deterministic trust-evaluation dataset that can
subsequently be submitted to GreenTrustChain.sol.

The exact aggregation weights must be specified by the
experimental configuration. They are NOT silently invented here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict

import numpy as np
import pandas as pd


# ================================================================
# PATHS
# ================================================================

PROJECT_ROOT = (
    Path(__file__).resolve().parents[1]
)

DEFAULT_INPUT = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "GSCROF_benchmark_95556.csv"
)

RESULT_DIRECTORY = (
    PROJECT_ROOT
    / "results"
    / "trust"
)

DEFAULT_OUTPUT = (
    RESULT_DIRECTORY
    / "trust_scores.csv"
)

DEFAULT_METADATA = (
    RESULT_DIRECTORY
    / "trust_metadata.json"
)


# ================================================================
# TRUST SCALE
# ================================================================

TRUST_MIN = 0
TRUST_MAX = 10_000


# ================================================================
# DATA MODEL
# ================================================================

@dataclass(frozen=True)
class TrustWeights:

    historical_reliability: float

    data_consistency: float

    communication_reliability: float

    contextual_trust: float

    def validate(self) -> None:

        values = [
            self.historical_reliability,
            self.data_consistency,
            self.communication_reliability,
            self.contextual_trust,
        ]

        if any(
            value < 0
            for value in values
        ):
            raise ValueError(
                "Trust weights cannot be negative."
            )

        total = sum(values)

        if not np.isclose(
            total,
            1.0,
            atol=1e-9,
        ):
            raise ValueError(
                "Trust weights must sum to 1.0. "
                f"Current sum = {total}"
            )


# ================================================================
# CONFIGURATION
# ================================================================


def load_weights(
    configuration_file: Path,
) -> TrustWeights:
    """
    Load the trust aggregation weights from an external JSON
    configuration.

    This prevents the implementation from silently introducing
    experimental assumptions.
    """

    if not configuration_file.exists():

        raise FileNotFoundError(
            "Trust configuration not found:\n"
            f"{configuration_file}\n\n"
            "Create the configuration explicitly before running "
            "the trust engine."
        )

    with configuration_file.open(
        "r",
        encoding="utf-8",
    ) as file:

        config = json.load(file)

    weights = config["trust_weights"]

    result = TrustWeights(
        historical_reliability=float(
            weights[
                "historical_reliability"
            ]
        ),

        data_consistency=float(
            weights[
                "data_consistency"
            ]
        ),

        communication_reliability=float(
            weights[
                "communication_reliability"
            ]
        ),

        contextual_trust=float(
            weights[
                "contextual_trust"
            ]
        ),
    )

    result.validate()

    return result


# ================================================================
# INPUT VALIDATION
# ================================================================

REQUIRED_COLUMNS = [
    "row_id",
    "prosumer_id",
    "feeder_id",
]


def validate_input(
    dataframe: pd.DataFrame,
) -> None:

    missing = [
        column
        for column in REQUIRED_COLUMNS
        if column not in dataframe.columns
    ]

    if missing:

        raise ValueError(
            "Required dataset columns are missing: "
            + ", ".join(missing)
        )

    if dataframe.empty:

        raise ValueError(
            "Dataset contains no records."
        )


# ================================================================
# NORMALIZATION
# ================================================================


def min_max_normalize(
    series: pd.Series,
) -> pd.Series:
    """
    Normalize a numeric series to [0,1].

    Constant values receive 1.0 because there is no observed
    variation within that dimension.
    """

    numeric = pd.to_numeric(
        series,
        errors="coerce",
    )

    minimum = numeric.min()

    maximum = numeric.max()

    if pd.isna(minimum) or pd.isna(maximum):

        raise ValueError(
            "Cannot normalize an empty or invalid series."
        )

    if np.isclose(
        minimum,
        maximum,
    ):

        return pd.Series(
            1.0,
            index=series.index,
        )

    return (numeric - minimum) / (maximum - minimum)


# ================================================================
# HISTORICAL RELIABILITY
# ================================================================


def calculate_historical_reliability(
    dataframe: pd.DataFrame,
) -> pd.Series:
    """
    Historical reliability estimates participant consistency
    from previous observations.

    The implementation uses the available historical trust
    evidence when trust_score exists.

    If trust_score is absent, this dimension cannot be silently
    reconstructed from unrelated variables.
    """

    if "trust_score" not in dataframe.columns:

        raise ValueError(
            "Historical reliability requires an existing "
            "'trust_score' field or an explicitly defined "
            "historical reliability variable."
        )

    trust = pd.to_numeric(
        dataframe["trust_score"],
        errors="coerce",
    )

    if trust.isna().any():

        raise ValueError(
            "Historical trust contains missing/non-numeric values."
        )

    if (trust.min() < TRUST_MIN or trust.max() > TRUST_MAX):

        raise ValueError(
            "Existing trust values must be within [0,10000]."
        )

    return (trust / TRUST_MAX)


# ================================================================
# DATA CONSISTENCY
# ================================================================


def calculate_data_consistency(
    dataframe: pd.DataFrame,
) -> pd.Series:
    """
    Measure row-level consistency using the available operational
    variables.

    The method uses normalized deviation from the participant's
    historical median.

    Higher consistency -> higher trust.
    """

    operational_columns = [
        "power_kw",
        "voltage_pu",
        "loss_index",
        "curtailment_index",
        "carbon_proxy",
    ]

    available = [
        column
        for column in operational_columns
        if column in dataframe.columns
    ]

    if not available:

        raise ValueError(
            "No operational variables are available for "
            "data-consistency evaluation."
        )

    working = dataframe[available].apply(
        pd.to_numeric,
        errors="coerce",
    )

    if working.isna().any().any():

        raise ValueError(
            "Operational data contains missing/non-numeric values."
        )

    normalized = pd.DataFrame(index=dataframe.index)

    for column in available:

        normalized[column] = min_max_normalize(working[column])

    """
    Consistency is calculated from the distance of each record
    from the participant-level historical median.
    """

    if "prosumer_id" in dataframe.columns:

        median_values = normalized.groupby(dataframe["prosumer_id"])[available].transform("median")

    else:

        median_values = pd.DataFrame(
            np.tile(
                normalized[available].median().values,
                (len(normalized), 1),
            ),
            index=normalized.index,
            columns=available,
        )

    deviation = (normalized[available] - median_values).abs()

    mean_deviation = deviation.mean(axis=1)

    consistency = 1.0 - mean_deviation

    return consistency.clip(0.0, 1.0)


# ================================================================
# COMMUNICATION RELIABILITY
# ================================================================


def calculate_communication_reliability(
    dataframe: pd.DataFrame,
) -> pd.Series:
    """
    Calculate communication reliability only when explicit
    communication evidence is present in the dataset.

    Supported fields:

        communication_reliability
        communication_success
        packet_delivery_ratio
    """

    if ("communication_reliability" in dataframe.columns):

        values = pd.to_numeric(dataframe["communication_reliability"], errors="coerce")

        return normalize_probability(values, "communication_reliability")

    if ("communication_success" in dataframe.columns):

        values = pd.to_numeric(dataframe["communication_success"], errors="coerce")

        return normalize_probability(values, "communication_success")

    if ("packet_delivery_ratio" in dataframe.columns):

        values = pd.to_numeric(dataframe["packet_delivery_ratio"], errors="coerce")

        return normalize_probability(values, "packet_delivery_ratio")

    raise ValueError(
        "No explicit communication reliability variable "
        "exists in the dataset. Add one or define a validated "
        "mapping before calculating this trust dimension."
    )


# ================================================================
# PROBABILITY NORMALIZATION
# ================================================================


def normalize_probability(
    values: pd.Series,
    field_name: str,
) -> pd.Series:

    if values.isna().any():

        raise ValueError(
            f"{field_name} contains missing values."
        )

    minimum = values.min()

    maximum = values.max()

    if (minimum < 0 or maximum > 1):

        raise ValueError(
            f"{field_name} must be normalized to [0,1]."
        )

    return values.clip(0.0, 1.0)


# ================================================================
# CONTEXTUAL OPERATIONAL TRUST
# ================================================================


def calculate_contextual_trust(
    dataframe: pd.DataFrame,
) -> pd.Series:
    """
    Calculate contextual trust from explicit contextual evidence.

    Supported variables:

        contextual_trust
        operational_trust
        context_score

    No synthetic contextual variable is generated if none exists.
    """

    candidates = [
        "contextual_trust",
        "operational_trust",
        "context_score",
    ]

    for column in candidates:

        if column in dataframe.columns:

            values = pd.to_numeric(dataframe[column], errors="coerce")

            return min_max_normalize(values).clip(0.0, 1.0)

    raise ValueError(
        "No explicit contextual/operational trust field "
        "is available in the dataset."
    )


# ================================================================
# TRUST AGGREGATION
# ================================================================


def aggregate_trust(
    historical: pd.Series,
    consistency: pd.Series,
    communication: pd.Series,
    contextual: pd.Series,
    weights: TrustWeights,
) -> pd.Series:
    """
    Weighted multidimensional trust aggregation.

    T_i =
        w_H H_i
        + w_D D_i
        + w_C C_i
        + w_X X_i

    where:

        H_i = historical reliability
        D_i = data consistency
        C_i = communication reliability
        X_i = contextual operational trust

    The normalized result is converted to the Solidity-compatible
    fixed-point representation [0,10000].
    """

    weights.validate()

    normalized = (
        weights.historical_reliability * historical
    ) + (
        weights.data_consistency * consistency
    ) + (
        weights.communication_reliability * communication
    ) + (
        weights.contextual_trust * contextual
    )

    normalized = normalized.clip(0.0, 1.0)

    return np.rint(normalized * TRUST_MAX).astype(np.int64)


# ================================================================
# VERIFICATION LEVEL
# ================================================================


def determine_verification_level(
    trust_score: pd.Series,
) -> pd.Series:
    """
    Convert trust score into the experimental verification class.

    IMPORTANT:
    Thresholds must correspond to those defined in the Solidity
    contract and Section 3.4.

    They are therefore loaded from configuration rather than
    silently hard-coded here.
    """

    raise NotImplementedError(
        "Verification thresholds must be supplied from the "
        "frozen GreenTrustChain experimental configuration."
    )


# ================================================================
# DATASET FINGERPRINT
# ================================================================


def calculate_dataset_hash(
    dataframe: pd.DataFrame,
) -> str:
    """
    Generate a deterministic hash from the serialized input
    dataframe used for the trust calculation.
    """

    serialized = dataframe.to_csv(index=False).encode("utf-8")

    return hashlib.sha256(serialized).hexdigest()


# ================================================================
# MAIN TRUST PIPELINE
# ================================================================


def calculate_trust(
    dataframe: pd.DataFrame,
    weights: TrustWeights,
) -> pd.DataFrame:
    """
    Execute the multidimensional trust pipeline.
    """

    validate_input(dataframe)

    historical = calculate_historical_reliability(dataframe)

    consistency = calculate_data_consistency(dataframe)

    communication = calculate_communication_reliability(dataframe)

    contextual = calculate_contextual_trust(dataframe)

    trust_score = aggregate_trust(
        historical,
        consistency,
        communication,
        contextual,
        weights,
    )

    result = dataframe.copy()

    result["historical_reliability"] = historical

    result["data_consistency"] = consistency

    result["communication_reliability"] = communication

    result["contextual_trust"] = contextual

    result["computed_trust_score"] = trust_score

    return result


# ================================================================
# OUTPUT
# ================================================================


def save_results(
    result: pd.DataFrame,
    dataset_hash: str,
    weights: TrustWeights,
) -> None:

    RESULT_DIRECTORY.mkdir(parents=True, exist_ok=True)

    result.to_csv(DEFAULT_OUTPUT, index=False)

    metadata = {

        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),

        "trust_scale": {"minimum": TRUST_MIN, "maximum": TRUST_MAX},

        "aggregation": {
            "historical_reliability": weights.historical_reliability,
            "data_consistency": weights.data_consistency,
            "communication_reliability": weights.communication_reliability,
            "contextual_trust": weights.contextual_trust,
        },

        "dataset_hash": dataset_hash,

        "records": int(len(result)),

        "output": str(DEFAULT_OUTPUT),
    }

    with DEFAULT_METADATA.open("w", encoding="utf-8") as file:

        json.dump(metadata, file, indent=2)


# ================================================================
# CLI
# ================================================================


def parse_arguments():

    parser = argparse.ArgumentParser(
        description=("Calculate GreenTrustChain " "multidimensional trust.")
    )

    parser.add_argument("--dataset", type=Path, default=DEFAULT_INPUT)

    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help=("JSON file containing the frozen " "trust aggregation configuration."),
    )

    return parser.parse_args()


# ================================================================
# ENTRY POINT
# ================================================================


def main():

    args = parse_arguments()

    if not args.dataset.exists():

        raise FileNotFoundError(f"Dataset not found: {args.dataset}")

    dataframe = pd.read_csv(args.dataset)

    weights = load_weights(args.config)

    print("GreenTrustChain Trust Engine")

    print("----------------------------")

    print(f"Records: {len(dataframe):,}")

    print("Trust scale: [0, 10000]")

    print("Weights:")

    print(f"  Historical reliability : {weights.historical_reliability}")

    print(f"  Data consistency       : {weights.data_consistency}")

    print(f"  Communication          : {weights.communication_reliability}")

    print(f"  Contextual             : {weights.contextual_trust}")

    result = calculate_trust(dataframe, weights)

    dataset_hash = calculate_dataset_hash(dataframe)

    save_results(result, dataset_hash, weights)

    print("\nTrust computation completed.")

    print(f"Output: {DEFAULT_OUTPUT}")

    print(f"Metadata: {DEFAULT_METADATA}")


if __name__ == "__main__":

    main()
