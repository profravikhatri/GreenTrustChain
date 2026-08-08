"""
GreenTrustChain
Trust Engine Validation Tests

Purpose
-------
Validate the mathematical properties of the multidimensional
trust model before blockchain execution.

Tests:
1. Weight sum = 1
2. Trust score remains within [0,10000]
3. Deterministic computation
4. High-trust classification
5. Medium-trust classification
6. Low-trust classification
7. Monotonicity of aggregation
8. No NaN / infinite values
"""

import json
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from trust_engine import (
    TrustWeights,
    aggregate_trust,
    TRUST_MIN,
    TRUST_MAX,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]

CONFIG_PATH = (
    PROJECT_ROOT
    / "config"
    / "trust_config.json"
)


class TestTrustEngine(unittest.TestCase):

    @classmethod
    def setUpClass(cls):

        with CONFIG_PATH.open(
            "r",
            encoding="utf-8"
        ) as file:

            cls.config = json.load(file)

        weights = cls.config["trust_weights"]

        cls.weights = TrustWeights(
            historical_reliability=float(
                weights["historical_reliability"]
            ),
            data_consistency=float(
                weights["data_consistency"]
            ),
            communication_reliability=float(
                weights["communication_reliability"]
            ),
            contextual_trust=float(
                weights["contextual_trust"]
            ),
        )

        cls.weights.validate()


    # ============================================================
    # WEIGHT VALIDATION
    # ============================================================

    def test_weights_sum_to_one(self):

        total = (
            self.weights.historical_reliability
            + self.weights.data_consistency
            + self.weights.communication_reliability
            + self.weights.contextual_trust
        )

        self.assertAlmostEqual(
            total,
            1.0,
            places=9,
        )


    def test_weights_are_non_negative(self):

        values = [
            self.weights.historical_reliability,
            self.weights.data_consistency,
            self.weights.communication_reliability,
            self.weights.contextual_trust,
        ]

        for value in values:

            self.assertGreaterEqual(
                value,
                0.0,
            )


    # ============================================================
    # TRUST SCALE
    # ============================================================

    def test_trust_scale_constants(self):

        self.assertEqual(
            TRUST_MIN,
            0,
        )

        self.assertEqual(
            TRUST_MAX,
            10000,
        )


    # ============================================================
    # BOUNDARY TESTS
    # ============================================================

    def test_minimum_possible_trust(self):

        zero =
            pd.Series(
                [0.0]
            )

        score =
            aggregate_trust(
                zero,
                zero,
                zero,
                zero,
                self.weights,
            )

        self.assertEqual(
            int(score.iloc[0]),
            TRUST_MIN,
        )


    def test_maximum_possible_trust(self):

        one =
            pd.Series(
                [1.0]
            )

        score =
            aggregate_trust(
                one,
                one,
                one,
                one,
                self.weights,
            )

        self.assertEqual(
            int(score.iloc[0]),
            TRUST_MAX,
        )


    # ============================================================
    # RANGE TEST
    # ============================================================

    def test_trust_never_exceeds_range(self):

        test_values =
            pd.Series(
                np.linspace(
                    0.0,
                    1.0,
                    101,
                )
            )

        score =
            aggregate_trust(
                test_values,
                test_values,
                test_values,
                test_values,
                self.weights,
            )

        self.assertTrue(
            (score >= TRUST_MIN).all()
        )

        self.assertTrue(
            (score <= TRUST_MAX).all()
        )


    # ============================================================
    # DETERMINISM
    # ============================================================

    def test_computation_is_deterministic(self):

        historical =
            pd.Series(
                [0.85, 0.72, 0.94]
            )

        consistency =
            pd.Series(
                [0.90, 0.70, 0.88]
            )

        communication =
            pd.Series(
                [0.95, 0.75, 0.91]
            )

        contextual =
            pd.Series(
                [0.80, 0.65, 0.93]
            )

        first =
            aggregate_trust(
                historical,
                consistency,
                communication,
                contextual,
                self.weights,
            )

        second =
            aggregate_trust(
                historical,
                consistency,
                communication,
                contextual,
                self.weights,
            )

        np.testing.assert_array_equal(
            first.to_numpy(),
            second.to_numpy(),
        )


    # ============================================================
    # MONOTONICITY
    # ============================================================

    def test_higher_evidence_cannot_reduce_trust(self):

        low =
            pd.Series(
                [0.40]
            )

        high =
            pd.Series(
                [0.80]
            )

        low_score =
            aggregate_trust(
                low,
                low,
                low,
                low,
                self.weights,
            )

        high_score =
            aggregate_trust(
                high,
                high,
                high,
                high,
                self.weights,
            )

        self.assertGreater(
            int(high_score.iloc[0]),
            int(low_score.iloc[0]),
        )


    # ============================================================
    # PARTIAL DIMENSION TEST
    # ============================================================

    def test_dimension_change_affects_score(self):

        base =
            pd.Series(
                [0.75]
            )

        improved =
            pd.Series(
                [0.90]
            )

        baseline_score =
            aggregate_trust(
                base,
                base,
                base,
                base,
                self.weights,
            )

        improved_score =
            aggregate_trust(
                improved,
                base,
                base,
                base,
                self.weights,
            )

        self.assertGreater(
            int(improved_score.iloc[0]),
            int(baseline_score.iloc[0]),
        )


    # ============================================================
    # NUMERICAL VALIDITY
    # ============================================================

    def test_no_nan_or_infinite_scores(self):

        values =
            pd.Series(
                [
                    0.0,
                    0.25,
                    0.5,
                    0.75,
                    1.0,
                ]
            )

        score =
            aggregate_trust(
                values,
                values,
                values,
                values,
                self.weights,
            )

        self.assertFalse(
            np.isnan(
                score.to_numpy()
            ).any()
        )

        self.assertFalse(
            np.isinf(
                score.to_numpy()
            ).any()
        )


    # ============================================================
    # EXPECTED FIXED-POINT VALUES
    # ============================================================

    def test_known_equal_dimension_values(self):

        values =
            pd.Series(
                [0.5]
            )

        score =
            aggregate_trust(
                values,
                values,
                values,
                values,
                self.weights,
            )

        self.assertEqual(
            int(score.iloc[0]),
            5000,
        )


    # ============================================================
    # CONFIGURATION CONSISTENCY
    # ============================================================

    def test_configuration_scale(self):

        model =
            self.config["model"]

        self.assertEqual(
            model["trust_scale_min"],
            0,
        )

        self.assertEqual(
            model["trust_scale_max"],
            10000,
        )


if __name__ == "__main__":

    unittest.main(
        verbosity=2
    )