#!/usr/bin/env python3
"""Writes CatalogEntries.kt from the iOS catalogue, GrogLog/Model/Catalog.swift, which stays the source of truth.

Run from anywhere after changing the Swift table: `android/scripts/catalog.py`.
"""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
swift = (root / "GrogLog/Model/Catalog.swift").read_text().splitlines()
out = root / "android/app/src/main/java/cc/blit/groglog/model/CatalogEntries.kt"

sizes = re.compile(r"^\s*private static let (\w+) = ServeSize\(\.(\w+), (\d+)\)$")
entry = re.compile(r'^\s*\("([^"]*)", \.(\w+), ([\d.]+), \[(.*)\]\),\s*$')
serve = re.compile(r"\((?:([a-zA-Z0-9]+)|\.init\(\.(\w+), ([\d.]+)\)), ([\d.]+)\)")


def upper(camel):
    return re.sub(r"(?<!^)([A-Z])", r"_\1", camel).upper()


def number(text):
    return text if "." in text else text + ".0"


def kotlin_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"'


constants = []
chunks = [[]]
count = 0
inside = False
for line in swift:
    if (m := sizes.match(line)):
        constants.append(f"private val {m[1]} = ServeSize({upper(m[2])}, {number(m[3])})")
        continue
    if "private static let entries:" in line:
        inside = True
        continue
    if not inside:
        continue
    if line.strip() == "]":
        break
    stripped = line.strip()
    if not stripped:
        chunks[-1].append("")
    elif stripped.startswith("//"):
        # A long function body would pass the JVM's 64 KB method limit, so the table is cut at a comment.
        if count >= 200 and chunks[-1] and not chunks[-1][-1].lstrip().startswith("//"):
            chunks.append([])
            count = 0
        chunks[-1].append("    " + stripped)
    else:
        m = entry.match(line)
        if not m:
            raise SystemExit(f"Unrecognised catalogue line: {line}")
        pairs = []
        for s in serve.finditer(m[4]):
            size = s[1] if s[1] else f"ServeSize({upper(s[2])}, {number(s[3])})"
            pairs.append(f"{size} to {number(s[4])}")
        chunks[-1].append(f"    e({kotlin_string(m[1])}, {upper(m[2])}, {number(m[3])}, {', '.join(pairs)}),")
        count += 1

lines = [
    "// Generated from GrogLog/Model/Catalog.swift by android/scripts/catalog.py. Edit the Swift table and regenerate.",
    "",
    "package cc.blit.groglog.model",
    "",
    "import cc.blit.groglog.model.DrinkCategory.*",
    "import cc.blit.groglog.model.Vessel.*",
    "",
    *constants,
    "",
    "private fun e(name: String, category: DrinkCategory, abv: Double, vararg serves: Pair<ServeSize, Double>) =",
    "    CatalogEntry(name, category, abv, serves.toList())",
    "",
    "/**",
    " * Ordered by popularity within each category. The long-press sheet lists a whole category unfiltered, so the common",
    " * choices come first and the rest are reachable by search.",
    " */",
    "internal val catalogEntries: List<CatalogEntry> by lazy {",
    "    " + " + ".join(f"part{i}()" for i in range(len(chunks))),
    "}",
]
for i, chunk in enumerate(chunks):
    lines += ["", f"private fun part{i}() = listOf(", *chunk, ")"]
out.write_text("\n".join(lines) + "\n")
print(f"{out.relative_to(root)}: {sum(1 for c in chunks for l in c if l.lstrip().startswith('e('))} entries in {len(chunks)} parts")
