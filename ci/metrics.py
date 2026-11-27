"""Produce JSON evidence from JaCoCo and a successful simulated deployment."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time
from xml.etree import ElementTree


def coverage(args):
    report = ElementTree.parse(args.report).getroot()
    counts = report.find("./counter[@type='LINE']")
    if counts is None:
        raise SystemExit("JaCoCo did not produce an aggregate LINE counter")
    covered, missed = (int(counts.attrib[key]) for key in ("covered", "missed"))
    if min(covered, missed, args.compile_seconds) < 0 or covered + missed == 0:
        raise SystemExit("Invalid coverage or compile measurement")
    return {
        "schema_version": 1,
        "coverage_percent": round(100 * covered / (covered + missed), 4),
        "lines_covered": covered,
        "lines_missed": missed,
        "compile_seconds": args.compile_seconds,
    }


def deployment(args):
    metrics = json.loads(args.coverage.read_text(encoding="utf-8"))
    elapsed = time.monotonic_ns() - args.start_ns
    if elapsed <= 0 or not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise SystemExit("Invalid deployment measurement or commit SHA")
    return {
        **metrics,
        "event": "compose_smoke_success",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "deploy_seconds": round(elapsed / 1_000_000_000, 3),
        "repository": args.repository,
        "commit": args.commit,
        "run_id": args.run_id,
        "run_attempt": args.run_attempt,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    report = commands.add_parser("coverage")
    report.add_argument("report", type=Path)
    report.add_argument("compile_seconds", type=int)
    report.set_defaults(collect=coverage)
    deploy = commands.add_parser("deployment")
    deploy.add_argument("coverage", type=Path)
    deploy.add_argument("start_ns", type=int)
    deploy.add_argument("repository")
    deploy.add_argument("commit")
    deploy.add_argument("run_id", type=int)
    deploy.add_argument("run_attempt", type=int)
    deploy.set_defaults(collect=deployment)
    args = parser.parse_args()
    print(json.dumps(args.collect(args), allow_nan=False))


if __name__ == "__main__":
    main()
