# -*- coding: utf-8 -*-
"""Calculate the applicability-domain distance index (AD index D).

The original plot_figure7_modified.py reads a precomputed AD_D column from
candidates.csv. It does not calculate D. This standalone implementation uses
the definition recorded in the accompanying summary.json file.

Definition:
    TV(x, h) = 0.5 * sum_k |x_k - h_k|
    D(x) = min_h TV(x, h) / max_{i,j} TV(h_i, h_j)

Here, x is a candidate land-use composition and h is a historical land-use
composition. All six-component rows are normalized to sum to one.

Inputs:
1. A candidate Excel workbook containing sheets P=5%, P=10%, and P=33%,
   or a single CSV file with candidate land-use proportions.
2. A historical Excel/CSV file with at least two distinct land-use rows.
3. By default, columns A:F of both inputs must contain these categories,
   in order: Cropland, Forest, Grassland, Water, Impervious, Barren.
   Column positions are used, so source headers may be in any language.

Run:
    pip install numpy pandas openpyxl
    python calculate_AD_D.py

Output: One CSV containing the six land-use proportions, the nearest
historical configuration, the TV distance, and AD_D for each scenario.
The input files are not modified.
"""

from pathlib import Path

import numpy as np
import pandas as pd


# ==================== USER CONFIGURATION ====================
CANDIDATE_FILE = Path(r"D:\Hydrology\input\candidate_land_use.xlsx")
HISTORICAL_FILE = Path(r"D:\Hydrology\input\historical_land_use.xlsx")
OUTPUT_FILE = Path(r"D:\Hydrology\output\AD_D_results.csv")

CANDIDATE_SHEETS = ["P=5%", "P=10%", "P=33%"]
HISTORICAL_SHEET = "Historical"
LANDUSE_NAMES = ["Cropland", "Forest", "Grassland", "Water", "Impervious", "Barren"]
CANDIDATE_LANDUSE_COLS = [0, 1, 2, 3, 4, 5]   # Excel columns A:F
HISTORICAL_LANDUSE_COLS = [0, 1, 2, 3, 4, 5]  # Excel columns A:F

# Optional identifier column. If absent, use H1, H2, etc.
HISTORICAL_ID_COLUMN = "Year"
BATCH_SIZE = 5000
# =============================================================


def read_table(path: Path, sheet_name=None) -> pd.DataFrame:
    """Read a CSV file or an Excel worksheet."""
    if not path.is_file():
        raise FileNotFoundError(f"Input file not found: {path}")
    if path.suffix.lower() == ".csv":
        return pd.read_csv(path, encoding="utf-8-sig")
    if path.suffix.lower() in {".xlsx", ".xls"}:
        return pd.read_excel(path, sheet_name=sheet_name)
    raise ValueError(f"Unsupported input format: {path.suffix}")


def extract_landuse(frame: pd.DataFrame, label: str, column_indices):
    """Extract land-use fractions by position and normalize each nonempty row."""
    if len(column_indices) != 6 or len(set(column_indices)) != 6:
        raise ValueError("Exactly six distinct land-use column indices are required")
    if min(column_indices) < 0 or max(column_indices) >= len(frame.columns):
        raise ValueError(f"{label}: land-use column indices are outside the input table")

    numeric = frame.iloc[:, column_indices].apply(pd.to_numeric, errors="coerce")
    valid_rows = ~numeric.isna().all(axis=1)
    frame = frame.loc[valid_rows].copy()
    values = numeric.loc[valid_rows].to_numpy(dtype=float)

    if len(values) == 0:
        raise ValueError(f"{label}: no valid land-use rows")
    if not np.isfinite(values).all():
        raise ValueError(f"{label}: missing or nonnumeric land-use values")
    if (values < 0).any():
        raise ValueError(f"{label}: negative land-use proportions")

    totals = values.sum(axis=1)
    if (totals <= 0).any():
        raise ValueError(f"{label}: at least one land-use row sums to zero")

    normalized = values / totals[:, None]
    return frame, values, normalized


def tv_distances(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Compute pairwise total-variation distances between two row sets."""
    return 0.5 * np.abs(a[:, None, :] - b[None, :, :]).sum(axis=2)


def calculate_d(candidates: np.ndarray, historical: np.ndarray, batch_size=BATCH_SIZE):
    """Return nearest TV distances, nearest indices, D, and historical diameter."""
    if len(historical) < 2:
        raise ValueError("At least two historical compositions are required")

    historical_pairwise_tv = tv_distances(historical, historical)
    historical_diameter = float(historical_pairwise_tv.max())
    if historical_diameter <= 0:
        raise ValueError("Historical compositions have zero TV diameter")

    nearest_tvs = np.empty(len(candidates), dtype=float)
    nearest_indices = np.empty(len(candidates), dtype=int)
    for start in range(0, len(candidates), batch_size):
        end = min(start + batch_size, len(candidates))
        distances = tv_distances(candidates[start:end], historical)
        nearest_indices[start:end] = np.argmin(distances, axis=1)
        nearest_tvs[start:end] = distances[
            np.arange(end - start), nearest_indices[start:end]
        ]

    d_values = nearest_tvs / historical_diameter
    return nearest_tvs, nearest_indices, d_values, historical_diameter


def main():
    hist = read_table(HISTORICAL_FILE, HISTORICAL_SHEET)
    hist, _, hist_normalized = extract_landuse(
        hist, "Historical data", HISTORICAL_LANDUSE_COLS
    )

    if HISTORICAL_ID_COLUMN in hist.columns:
        historical_ids = hist[HISTORICAL_ID_COLUMN].astype(str).to_numpy()
    else:
        historical_ids = np.array([f"H{i+1}" for i in range(len(hist))])

    # A CSV has one dataset; an Excel workbook may have three scenario sheets.
    scenario_names = (
        ["CSV"] if CANDIDATE_FILE.suffix.lower() == ".csv"
        else CANDIDATE_SHEETS
    )
    results = []
    for scenario in scenario_names:
        cand = read_table(CANDIDATE_FILE, scenario)
        _, cand_raw, cand_normalized = extract_landuse(
            cand, f"Candidates {scenario}", CANDIDATE_LANDUSE_COLS
        )
        nearest_tvs, nearest_indices, d, diameter = calculate_d(
            cand_normalized, hist_normalized
        )

        # Export only the six original land-use proportions and D-related fields.
        out = pd.DataFrame(cand_raw, columns=LANDUSE_NAMES)
        out.insert(0, "scenario", scenario)
        out["nearest_historical_id"] = historical_ids[nearest_indices]
        out["TV_nearest_frac"] = nearest_tvs
        out["TV_nearest_pct"] = nearest_tvs * 100.0
        out["AD_D"] = d
        results.append(out)
        print(
            f"{scenario}: n={len(out)}, historical TV diameter={diameter:.12g}, "
            f"D range=[{d.min():.6g}, {d.max():.6g}]"
        )

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    pd.concat(results, ignore_index=True).to_csv(
        OUTPUT_FILE, index=False, encoding="utf-8-sig", float_format="%.15g"
    )
    print(f"Results saved to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
