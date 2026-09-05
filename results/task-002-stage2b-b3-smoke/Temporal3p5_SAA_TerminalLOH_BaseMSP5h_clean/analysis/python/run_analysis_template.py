"""Small, path-driven analysis entry for derived experiment packages.

It only inventories caller-supplied CSV outputs; it never points at historical
project results and never writes into the canonical template's program tree.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import csv

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    files = sorted(p for p in args.input_root.rglob("*.csv") if p.is_file())
    args.output_root.mkdir(parents=True, exist_ok=True)
    out = args.output_root / "analysis_input_inventory.csv"
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["relative_path", "bytes"])
        for path in files:
            writer.writerow([path.relative_to(args.input_root).as_posix(), path.stat().st_size])
    print(f"Inventoried {len(files)} CSV files into {out}")

if __name__ == "__main__":
    main()
