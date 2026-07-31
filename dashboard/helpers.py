import math

BAND_ORDER = ['sub_bass', 'bass', 'low_mid', 'mid', 'high_mid', 'high']

A_WEIGHT_OFFSETS = {
    'sub_bass': -22.4,
    'bass': -11.0,
    'low_mid': -4.8,
    'mid': 0.0,
    'high_mid': 1.2,
    'high': -1.0,
}


def linear_to_dbfs(power: float) -> float:
    return 10 * math.log10(power + 1e-18)


def dbfs_to_linear(dbfs: float) -> float:
    return 10 ** (dbfs / 10)


def weighted_overall(bands: dict) -> float:
    power = sum(
        dbfs_to_linear(bands.get(b, -80) + A_WEIGHT_OFFSETS.get(b, 0))
        for b in BAND_ORDER
    )
    return linear_to_dbfs(power)


def clamp(value: float, lo: float = -80.0, hi: float = 0.0) -> float:
    return max(lo, min(hi, value))
