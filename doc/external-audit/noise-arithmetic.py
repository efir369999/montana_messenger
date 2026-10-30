#!/usr/bin/env python3
"""Exact arithmetic for NETWORK-NOISE-CRITIQUE.md; no network or runtime tests."""

import json
from fractions import Fraction


def exact(value):
    return {"fraction": str(value), "decimal": float(value)}


rows = []
for interval in (Fraction(60), Fraction(10), Fraction(1), Fraction(1, 10)):
    mib = Fraction(4096 * 86400, 2**20) / interval
    rows.append({"interval_seconds": exact(interval), "one_way_MiB_day": exact(mib),
                 "two_way_MiB_day": exact(2 * mib)})

gib = 2**30
print(json.dumps({
    "kind": "analytical examples; not observed product performance or privacy",
    "constant_schedule": rows,
    "one_GiB_at_4096_bytes_per_second_seconds": exact(Fraction(gib, 4096)),
    "one_GiB_at_4096_bytes_per_second_hours": exact(Fraction(gib, 4096 * 3600)),
    "one_GiB_per_minute_bytes_per_second": exact(Fraction(gib, 60)),
    "one_GiB_per_minute_Mbit_per_second": exact(Fraction(gib * 8, 60 * 10**6)),
    "same_rate_GiB_per_day": exact(Fraction(86400, 60)),
    "same_rate_TiB_per_day": exact(Fraction(86400, 60 * 1024)),
    "uniform_example": {"N": 10, "r0": 0, "r1": 5,
                        "early_departure_probability_r0": exact(Fraction(5, 10)),
                        "early_departure_probability_r1": exact(Fraction(0))},
    "additive_Poisson_example": {
        "lambda_per_second": 1, "s_per_second": 1, "T_seconds": 120,
        "TV_lower_bound": exact(1 - Fraction(4 * (2 * 1 + 1), 1**2 * 120)),
        "equal_prior_optimal_success_lower_bound": exact(Fraction(19, 20)),
        "scope": "toy model only; no Montana parameter or measurement"
    },
}, indent=2))
