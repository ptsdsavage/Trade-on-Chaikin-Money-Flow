"""
Checks how accurate the CMF signal (and session_signal) predictions were for a
given day's signal log, by comparing each signal to the actual price movement
N minutes later.

Usage:
    python check_accuracy.py [YYYY-MM-DD] [--horizon MINUTES] [--threshold PCT]

Defaults to today's date, a 5-minute look-ahead horizon, and a 0.0% flat
threshold (any nonzero move counts as up/down).
"""

import argparse
import os
import sys
from datetime import date

import pandas as pd

BULLISH = "BULLISH"
BEARISH = "BEARISH"
NEUTRAL = "NEUTRAL"


def classify(signal: str) -> str:
    signal = str(signal)
    if signal.startswith(BULLISH):
        return BULLISH
    if signal.startswith(BEARISH):
        return BEARISH
    return NEUTRAL


def actual_direction(pct_change: float, threshold_pct: float) -> str:
    if pct_change > threshold_pct:
        return BULLISH
    if pct_change < -threshold_pct:
        return BEARISH
    return NEUTRAL


def score_column(df: pd.DataFrame, signal_col: str, horizon: int, threshold_pct: float) -> dict:
    future_close = df["close"].shift(-horizon)
    pct_change = (future_close - df["close"]) / df["close"] * 100.0

    predicted = df[signal_col].apply(classify)
    actual = pct_change.apply(lambda p: actual_direction(p, threshold_pct) if pd.notna(p) else None)

    evaluated = predicted.notna() & actual.notna() & (predicted != NEUTRAL)
    total = int(evaluated.sum())
    correct = int(((predicted == actual) & evaluated).sum())

    per_class = {}
    for cls in (BULLISH, BEARISH):
        mask = evaluated & (predicted == cls)
        cls_total = int(mask.sum())
        cls_correct = int(((predicted == actual) & mask).sum())
        per_class[cls] = (cls_correct, cls_total)

    return {
        "total": total,
        "correct": correct,
        "per_class": per_class,
    }


def print_report(title: str, result: dict) -> None:
    total, correct = result["total"], result["correct"]
    accuracy = (correct / total * 100.0) if total else float("nan")
    print(f"\n{title}")
    print(f"  Overall: {correct}/{total} correct ({accuracy:.1f}%)")
    for cls, (cls_correct, cls_total) in result["per_class"].items():
        cls_acc = (cls_correct / cls_total * 100.0) if cls_total else float("nan")
        print(f"  {cls:8s}: {cls_correct}/{cls_total} correct ({cls_acc:.1f}%)")


def report_rows(source: str, result: dict) -> list[dict]:
    total, correct = result["total"], result["correct"]
    rows = [{
        "source": source,
        "class": "OVERALL",
        "correct": correct,
        "total": total,
        "accuracy_pct": (correct / total * 100.0) if total else float("nan"),
    }]
    for cls, (cls_correct, cls_total) in result["per_class"].items():
        rows.append({
            "source": source,
            "class": cls,
            "correct": cls_correct,
            "total": cls_total,
            "accuracy_pct": (cls_correct / cls_total * 100.0) if cls_total else float("nan"),
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Score CMF signal accuracy against actual price movement.")
    parser.add_argument("day", nargs="?", default=str(date.today()), help="Session date (YYYY-MM-DD), defaults to today.")
    parser.add_argument("--horizon", type=int, default=5, help="Minutes ahead to check actual price movement (default: 5).")
    parser.add_argument("--threshold", type=float, default=0.0, help="Percent move required to count as up/down, else NEUTRAL (default: 0.0).")
    args = parser.parse_args()

    app_dir = os.path.dirname(os.path.abspath(__file__))
    log_path = os.path.join(app_dir, f"spy_signal_log_{args.day}.csv")
    if not os.path.exists(log_path):
        print(f"Signal log not found: {log_path}", file=sys.stderr)
        sys.exit(1)

    df = pd.read_csv(log_path, parse_dates=["timestamp"]).sort_values("timestamp").reset_index(drop=True)
    if df.empty:
        print(f"Signal log is empty: {log_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Signal log: {log_path}")
    print(f"Rows: {len(df)}  |  Horizon: {args.horizon} min  |  Flat threshold: {args.threshold:.2f}%")

    signal_result = score_column(df, "signal", args.horizon, args.threshold)
    session_result = score_column(df, "session_signal", args.horizon, args.threshold)

    print_report("Per-minute signal", signal_result)
    print_report("Session signal", session_result)

    rows = report_rows("signal", signal_result) + report_rows("session_signal", session_result)
    out_path = os.path.join(app_dir, f"spy_accuracy_{args.day}.csv")
    pd.DataFrame(rows).to_csv(out_path, index=False)
    print(f"\nSaved report -> {out_path}")


if __name__ == "__main__":
    main()
