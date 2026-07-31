import math

BAND_ORDER = ['sub_bass', 'bass', 'low_mid', 'mid', 'high_mid', 'high']


def linear_to_dbfs(power: float) -> float:
    return 10 * math.log10(power + 1e-18)


def dbfs_to_linear(dbfs: float) -> float:
    return 10 ** (dbfs / 10)
