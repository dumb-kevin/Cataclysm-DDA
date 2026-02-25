#!/usr/bin/env python3
"""Format mayfail test failure JSON reports into a markdown PR comment fragment.

Reads one or more JSON files produced by cata_test --mayfail-report and outputs
a markdown fragment suitable for aggregation into a GitHub PR comment.

Usage:
    format_mayfail_comment.py [--job-title TITLE] file1.json [file2.json ...]
"""

import argparse
import json
import sys
from pathlib import Path


def load_failures(paths):
    """Load and merge failures from multiple JSON files."""
    failures = []
    for p in paths:
        path = Path(p)
        if not path.exists() or path.stat().st_size == 0:
            continue
        try:
            with open(path) as f:
                data = json.load(f)
            if isinstance(data, list):
                failures.extend(data)
        except (json.JSONDecodeError, OSError):
            continue
    return failures


def deduplicate(failures):
    """Merge failures for the same test case (from different shards)."""
    by_test = {}
    for fail in failures:
        name = fail.get("test", "unknown")
        if name in by_test:
            by_test[name]["assertions"].extend(fail.get("assertions", []))
        else:
            by_test[name] = {
                "test": name,
                "tags": fail.get("tags", ""),
                "assertions": list(fail.get("assertions", [])),
            }
    return list(by_test.values())


def _sanitize_cell(text, max_len=200):
    """Sanitize text for use in markdown table cells or inline backticks."""
    text = text.replace("\n", " ").replace("\r", " ").replace("|", "\\|")
    if len(text) > max_len:
        text = text[:max_len] + "..."
    return text


def format_markdown(failures, job_title):
    """Format failures into a markdown fragment for one CI job."""
    if not failures:
        return ""

    lines = []
    for fail in failures:
        test_name = fail["test"]
        assertions = fail.get("assertions", [])
        if not assertions:
            continue

        first = assertions[0]
        loc = "{}:{}".format(first.get("file", "?"), first.get("line", "?"))

        lines.append(
            "**`{}`** | _{}_".format(test_name, job_title)
        )
        lines.append("")
        lines.append(
            "`{}`: `{}` -- expanded to `{}`".format(
                loc,
                _sanitize_cell(first.get("expression", "?")),
                _sanitize_cell(first.get("expanded", "?")),
            )
        )
        lines.append("")

        # Details spoiler with all assertions and messages
        lines.append("<details>")
        lines.append(
            "<summary>All failed assertions ({})</summary>".format(len(assertions))
        )
        lines.append("")
        lines.append("| Location | Assertion | Got |")
        lines.append("|----------|-----------|-----|")
        for a in assertions:
            a_loc = "{}:{}".format(a.get("file", "?"), a.get("line", "?"))
            lines.append(
                "| `{}` | `{}` | `{}` |".format(
                    a_loc,
                    _sanitize_cell(a.get("expression", "?")),
                    _sanitize_cell(a.get("expanded", "?")),
                )
            )

        # Collect all messages across assertions
        all_messages = []
        for a in assertions:
            all_messages.extend(a.get("messages", []))
        if all_messages:
            lines.append("")
            lines.append("INFO messages:")
            for msg in all_messages:
                lines.append("- {}".format(msg))

        lines.append("")
        lines.append("</details>")
        lines.append("")
        lines.append("---")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", help="JSON report files")
    parser.add_argument(
        "--job-title", default="Unknown Build", help="CI job title for this report"
    )
    args = parser.parse_args()

    if not args.files:
        return

    failures = load_failures(args.files)
    failures = deduplicate(failures)
    output = format_markdown(failures, args.job_title)
    if output:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
