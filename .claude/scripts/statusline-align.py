#!/usr/bin/env python3
"""Lay out status-line rows as left + right-aligned halves.

stdin: one row per line, "LEFT<TAB>RIGHT" (either may be empty; ANSI colors allowed).
argv[1]: usable width in cells. A row that does not fit drops padding to one space, then
cuts the LEFT half (the right half holds the alerts and counts, so it survives).
Width counts emoji and other East Asian Wide characters as 2 cells, escapes as 0.
"""
import re
import sys
import unicodedata

ANSI = re.compile(r"\x1b\[[0-9;]*m")
RESET = "\x1b[0m"


def cells(ch: str) -> int:
    if unicodedata.combining(ch) or ch in "️‍":
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def width(s: str) -> int:
    return sum(cells(c) for c in ANSI.sub("", s))


def cut(s: str, room: int) -> str:
    """Keep the first `room` cells of s (escapes kept), ending in an ellipsis."""
    if width(s) <= room:
        return s
    out, used, i = [], 0, 0
    while i < len(s):
        m = ANSI.match(s, i)
        if m:
            out.append(m.group())
            i = m.end()
            continue
        w = cells(s[i])
        if used + w > room - 1:
            break
        out.append(s[i])
        used += w
        i += 1
    return "".join(out) + "…" + RESET


def main() -> None:
    total = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 0
    for row in sys.stdin.read().splitlines():
        left, _, right = row.partition("\t")
        if not total or not right:
            print(left or right)
            continue
        gap = total - width(left) - width(right)
        if gap >= 1:
            print(left + " " * gap + right)
        else:
            room = total - width(right) - 1
            print((cut(left, room) + " " if room > 4 else "") + right)


if __name__ == "__main__":
    main()
