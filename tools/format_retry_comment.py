#!/usr/bin/env python3
"""Format retry_summary.txt into a markdown PR comment fragment.

Reads the tab-separated retry summary produced by gha_test_only.sh
and outputs a markdown table for aggregation into a GitHub PR comment.

Usage:
    format_retry_comment.py [--job-title TITLE] [--summary FILE]
"""

import argparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--job-title", default="Unknown Build",
        help="CI job title for this report"
    )
    parser.add_argument(
        "--summary", default="retry_summary.txt",
        help="Path to retry_summary.txt"
    )
    args = parser.parse_args()

    try:
        with open(args.summary) as f:
            lines = f.read().strip().splitlines()
    except FileNotFoundError:
        return

    if not lines:
        return

    entries = []
    for line in lines:
        parts = line.split("\t")
        if len(parts) == 3:
            result, attempts, test_name = parts
            entries.append((test_name, result, attempts))

    if not entries:
        return

    print("**{}**\n".format(args.job_title))
    print("| Test | Result | Attempts |")
    print("|------|--------|----------|")
    for test_name, result, attempts in sorted(entries):
        if result == "passed":
            icon = ":white_check_mark:"
        else:
            icon = ":x:"
        print("| `{}` | {} {} | {} |".format(
            test_name, icon, result, attempts))
    print()


if __name__ == "__main__":
    main()
