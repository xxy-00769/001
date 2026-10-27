"""Explicit software-only scenarios. No speed/distance sensor or actuator I/O."""
from __future__ import annotations

import argparse
import json
import math

from adas_protocol import Observation


def simulated_policy(observation, *, speed_kmh, limit_kmh, distance_m=None, turn="off"):
    """Toy scenario thresholds; never certify that a lane change is safe."""
    if not math.isfinite(speed_kmh) or not 0 <= speed_kmh <= 250:
        raise ValueError("Invalid simulated speed")
    if not math.isfinite(limit_kmh) or not 0 < limit_kmh <= 250:
        raise ValueError("Invalid simulated limit")
    if distance_m is not None and (not math.isfinite(distance_m) or distance_m < 0):
        raise ValueError("Invalid simulated distance")
    if turn not in ("off", "left", "right"):
        raise ValueError("Invalid turn input")
    kind = None
    if observation is not None:
        observation.validate()
        if turn == "left" and observation.flags & 1:
            kind = observation.left_kind
        elif turn == "right" and observation.flags & 2:
            kind = observation.right_kind
    ttc = distance_m / (speed_kmh / 3.6) if distance_m is not None and speed_kmh > 0 else None
    return {
        "source": "SOFTWARE_SIMULATION_ONLY",
        "simulated_speed_kmh": speed_kmh,
        "simulated_distance_m": distance_m,
        "simulated_overspeed": speed_kmh > limit_kmh,
        "simulated_proximity_alert": ttc is not None and ttc <= 2.0,
        "simulated_ttc_seconds": ttc,
        "simulated_turn_indicator": turn,
        "boundary_hint": ("unknown", "solid_candidate", "dashed_candidate")[kind or 0],
        "lane_change_safety": "NOT_ASSESSED",
        "actuator_output": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo", action="store_true", required=True)
    parser.parse_args()
    base = Observation(0x47, 0x09, 1, 0, 560, 400, 496, 360, 688,
                       880, 496, 920, 688, 280, 210, 0, 0)
    for scenario in (
        dict(speed_kmh=30, limit_kmh=50, turn="off"),
        dict(speed_kmh=60, limit_kmh=50, turn="right"),
        dict(speed_kmh=36, limit_kmh=50, distance_m=12, turn="left"),
    ):
        print(json.dumps(simulated_policy(base, **scenario)))


if __name__ == "__main__":
    main()
