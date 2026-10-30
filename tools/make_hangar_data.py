#!/usr/bin/env python3
"""Build the "Hangar Log Data" JSON file from Maintenance Record_be.accdb.

Read-only: uses mdbtools (mdb-export) on a copy of the database.

    python3 make_hangar_data.py <be.accdb> <out.json> [--compare previous.json]

With --compare, prints CHANGED or UNCHANGED (ignoring generatedAt), so a
new file is only written to Dropbox when something in Access changed.
"""
import csv
import datetime as dt
import io
import json
import re
import subprocess
import sys

PART_LINK = "f_EFD14865AD3146A4998A6AF6FA3FE4A4_Part"


def table(db, name):
    out = subprocess.run(["mdb-export", db, name], check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def parse_date(text):
    if not text:
        return None
    return dt.datetime.strptime(text.split()[0], "%m/%d/%y").date()


def number(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def clean_entry(text):
    # Some templates were pasted from VBA string code: '." & _ <newline> "Inspected'
    text = re.sub(r'"+\s*&\s*_\s*"+', " ", text)
    text = text.replace('""', '"')
    text = re.sub(r"[ \t]*\r?\n[ \t]*", " ", text)
    text = re.sub(r" {2,}", " ", text).strip()
    # Never carry old compression readings forward: "#1 79/80" -> "#1 [ ]/80"
    text = re.sub(r"(#\d)\s*\d{1,2}\s*/\s*80", r"\1 [ ]/80", text)
    return text


def build(db):
    links = {}
    for row in table(db, PART_LINK):
        links.setdefault(row["_Part"], []).append(int(row["Value"]))

    jobs = []
    for row in table(db, "Recurring Maintenance"):
        entry = (row.get("Logbook Entry") or "").strip()
        if not entry:
            continue
        hours = number(row.get("Logbook Time"))
        jobs.append({
            "recurringId": int(row["ID"]),
            "name": row["Inspection"].strip(),
            "entry": clean_entry(entry),
            "laborHours": round(hours, 2) if hours is not None else None,
            "equipmentIds": sorted(set(links.get(row.get("Part") or "", []))),
        })
    jobs.sort(key=lambda j: j["recurringId"])

    maintainers = [
        {"id": int(r["ID"]), "name": r["Maintainer"].strip(), "ap": r.get("A&P") == "1"}
        for r in table(db, "Maintainers") if r.get("Maintainer")
    ]
    maintainers.sort(key=lambda m: m["id"])

    last = None
    for r in table(db, "Maintenance Log"):
        hobbs, day = number(r.get("Hobbs")), parse_date(r.get("Date"))
        if hobbs is None or day is None:
            continue
        key = (hobbs, day, int(r["ID"]))
        if last is None or key > last:
            last = key
    last_hobbs = None
    if last:
        last_hobbs = {"value": round(last[0], 1), "date": last[1].isoformat(), "logId": last[2]}

    return {
        "schema": 1,
        "generatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "Maintenance Record_be.accdb",
        "lastHobbs": last_hobbs,
        "maintainers": maintainers,
        "jobs": jobs,
    }


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    data = build(argv[1])
    with open(argv[2], "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if "--compare" in argv:
        prev_path = argv[argv.index("--compare") + 1]
        try:
            with open(prev_path, encoding="utf-8") as f:
                prev = json.load(f)
        except (OSError, ValueError):
            prev = None
        same = prev is not None and {k: v for k, v in prev.items() if k != "generatedAt"} == \
            {k: v for k, v in data.items() if k != "generatedAt"}
        print("UNCHANGED" if same else "CHANGED")


if __name__ == "__main__":
    main(sys.argv)
