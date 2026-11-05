#!/usr/bin/env python3
"""
scripts/update_mmat.py

Automates the ingestion, validation, geocoding check, and manifest generation
when OPTN publishes a new Median MELD at Transplant (MMaT) dataset.

Usage:
    python3 scripts/update_mmat.py --input median-meld-sept2026.pdf
    python3 scripts/update_mmat.py --input new_mmat_data.csv
    python3 scripts/update_mmat.py --input https://optn.transplant.hrsa.gov/path/to/report.pdf
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
import urllib.parse
from datetime import datetime


def fetch_file(source: str) -> str:
    """If source is an HTTP/HTTPS URL, download to a temporary file."""
    if source.startswith("http://") or source.startswith("https://"):
        print(f"[*] Downloading remote OPTN release from: {source}")
        suffix = ".pdf" if ".pdf" in source.lower() else ".csv"
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        headers = {"User-Agent": "MELD3-MMaT-Updater/1.0"}
        req = urllib.request.Request(source, headers=headers)
        with urllib.request.urlopen(req) as resp, open(temp_file.name, "wb") as out:
            out.write(resp.read())
        return temp_file.name
    return source


def parse_pdf(pdf_path: str):
    """Extract Table 1 (Adult donor hospitals) from OPTN PDF using pdftotext -layout."""
    try:
        cmd = ["pdftotext", "-layout", pdf_path, "-"]
        output = subprocess.check_output(cmd).decode("utf-8", errors="ignore")
    except FileNotFoundError:
        sys.exit(
            "[!] Error: 'pdftotext' is not installed. Please install poppler-utils (brew install poppler / apt-get install poppler-utils)."
        )

    row_regex = re.compile(
        r"^\s*([A-Za-z]{2})\s+([A-Za-z0-9\.\,\'\s\-]+?)\s+([0-9A-Za-z]{6}\-[0-9A-Za-z]*)\s+(.+?)\s{2,}(\d{1,2})\s+(\d{2}/\d{2}/\d{4})\s+(\d{2}/\d{2}/\d{4})"
    )

    rows = []
    seen_codes = set()
    for line in output.split("\n"):
        m = row_regex.match(line)
        if not m:
            continue
        state, city, code, name, meld_str, begin, end = m.groups()
        state = state.strip().upper()
        city = city.strip().rstrip(",")
        code = code.strip()
        if code == "BERMDA-":
            code = "BERMDA-NMB"
        name = name.strip()
        meld = int(meld_str.strip())
        begin = begin.strip()
        end = end.strip()

        if code in seen_codes:
            continue
        seen_codes.add(code)

        rows.append({
            "state": state,
            "city": city,
            "donor_hospital_code": code,
            "donor_hospital_name": name,
            "median_meld": meld,
            "cohort_begin_date": begin,
            "cohort_end_date": end,
        })

    return rows


def parse_csv(csv_path: str):
    """Parse hospital records from a pre-formatted or raw CSV."""
    rows = []
    with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append({
                "state": r["state"].strip().upper(),
                "city": r["city"].strip().rstrip(","),
                "donor_hospital_code": r["donor_hospital_code"].strip(),
                "donor_hospital_name": r["donor_hospital_name"].strip(),
                "median_meld": int(r["median_meld"].strip()),
                "cohort_begin_date": r.get("cohort_begin_date", "09/01/2025").strip(),
                "cohort_end_date": r.get("cohort_end_date", "08/31/2026").strip(),
            })
    return rows


def geocode_city_state(city: str, state: str):
    """Geocode a city, state pair using OpenStreetMap Nominatim with fallback center."""
    try:
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        query = urllib.parse.urlencode({
            "city": city,
            "state": state,
            "country": "USA",
            "format": "json",
            "limit": 1,
        })
        url = f"https://nominatim.openstreetmap.org/search?{query}"
        headers = {"User-Agent": "MELD3-MMaT-Geocoding-Tool/1.0 (contact@surgeryai.org)"}
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5, context=ctx) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data and len(data) > 0:
                lat = round(float(data[0]["lat"]), 4)
                lon = round(float(data[0]["lon"]), 4)
                return [lat, lon]
    except Exception as e:
        print(f"    [!] Geocoding failed for {city}, {state}: {e}")
    return None


def main():
    parser = argparse.ArgumentParser(description="Update OPTN MMaT dataset and manifest.")
    parser.add_argument("--input", required=True, help="Path or URL to OPTN PDF or CSV file")
    parser.add_argument("--repo-root", default=".", help="Path to meld3 repository root")
    parser.add_argument("--dry-run", action="store_true", help="Validate and report without overwriting files")
    parser.add_argument("--geocode-missing", action="store_true", default=True, help="Auto-geocode missing cities")

    args = parser.parse_args()
    repo_root = os.path.abspath(args.repo_root)
    assets_dir = os.path.join(repo_root, "assets")
    csv_dest = os.path.join(assets_dir, "mmat_data.csv")
    coords_dest = os.path.join(assets_dir, "mmat_coordinates.json")
    manifest_dest = os.path.join(assets_dir, "mmat_manifest.json")

    # 1. Download / locate input file
    input_file = fetch_file(args.input)

    # 2. Extract rows
    if input_file.lower().endswith(".pdf"):
        print(f"[*] Extracting MMaT Table 1 from PDF: {input_file}")
        new_rows = parse_pdf(input_file)
    else:
        print(f"[*] Reading MMaT CSV: {input_file}")
        new_rows = parse_csv(input_file)

    if not new_rows or len(new_rows) < 1000:
        sys.exit(f"[!] Error: Expected >1,000 hospital records, found only {len(new_rows)}. Extraction aborted.")

    # Preserve full city names if previously known (heals truncated city column in OPTN PDFs)
    if os.path.exists(csv_dest):
        known_cities = {}
        with open(csv_dest, "r") as f:
            for r in csv.DictReader(f):
                known_cities[r["donor_hospital_code"]] = r["city"]
        for r in new_rows:
            code = r["donor_hospital_code"]
            if code in known_cities:
                prev_city = known_cities[code]
                if len(prev_city) > len(r["city"]) and prev_city.lower().startswith(r["city"].lower()[:5]):
                    r["city"] = prev_city

    # 3. Validation
    invalid_scores = [r for r in new_rows if r["median_meld"] < 6 or r["median_meld"] > 40]
    if invalid_scores:
        sys.exit(f"[!] Validation Error: {len(invalid_scores)} hospitals have scores outside 6..40 bounds!")

    first_row = new_rows[0]
    begin_date = first_row["cohort_begin_date"]
    end_date = first_row["cohort_end_date"]
    end_year = end_date.split("/")[-1]
    end_month = end_date.split("/")[0]
    cohort_version = f"{end_year}.{end_month}"

    print(f"[*] Successfully parsed {len(new_rows):,} donor hospitals.")
    print(f"[*] Detected Cohort Range: {begin_date} to {end_date} (Version {cohort_version})")

    # 4. Geocode verification
    with open(coords_dest, "r") as f:
        coords_map = json.load(f)

    missing_locations = set()
    for r in new_rows:
        key = f"{r['city'].lower()}|{r['state'].upper()}"
        if key not in coords_map:
            missing_locations.add((r["city"], r["state"]))

    if missing_locations:
        print(f"[*] Found {len(missing_locations)} newly introduced hospital location(s) not in coordinates dictionary.")
        if args.geocode_missing:
            for city, state in sorted(missing_locations):
                print(f"    --> Geocoding: {city}, {state}...")
                coords = geocode_city_state(city, state)
                if coords:
                    coords_map[f"{city.lower()}|{state.upper()}"] = coords
                    print(f"        Resolved: {coords}")
                else:
                    coords_map[f"{city.lower()}|{state.upper()}"] = [39.8283, -98.5795]
                    print(f"        Fallback to US center: [39.8283, -98.5795]")
    else:
        print("[✓] All hospital cities match existing coordinates. Zero missing coordinates.")

    # 5. Diff against previous version
    prev_rows = {}
    if os.path.exists(csv_dest):
        with open(csv_dest, "r") as f:
            for r in csv.DictReader(f):
                prev_rows[r["donor_hospital_code"]] = int(r["median_meld"])

    new_dict = {r["donor_hospital_code"]: r["median_meld"] for r in new_rows}
    common_codes = set(prev_rows.keys()) & set(new_dict.keys())
    added_codes = set(new_dict.keys()) - set(prev_rows.keys())
    removed_codes = set(prev_rows.keys()) - set(new_dict.keys())

    deltas = [new_dict[c] - prev_rows[c] for c in common_codes]
    avg_prev = sum(prev_rows.values()) / max(len(prev_rows), 1)
    avg_new = sum(new_dict.values()) / max(len(new_dict), 1)

    print("\n" + "=" * 60)
    print("OPTN MMaT UPDATE STATISTICAL AUDIT REPORT")
    print("=" * 60)
    print(f"Previous Hospital Count: {len(prev_rows):,}")
    print(f"New Hospital Count:      {len(new_rows):,}")
    print(f"Hospitals Added:         {len(added_codes)}")
    print(f"Hospitals Removed:       {len(removed_codes)}")
    print(f"National Average MMaT:   {avg_prev:.2f} -> {avg_new:.2f}")
    if deltas:
        print(f"Max Positive Shift:      +{max(deltas)} points")
        print(f"Max Negative Shift:      {min(deltas)} points")
        unchanged = sum(1 for d in deltas if d == 0)
        print(f"Unchanged Hospital Scores: {unchanged:,} ({unchanged / len(deltas) * 100:.1f}%)")
    print("=" * 60 + "\n")

    if args.dry_run:
        print("[!] Dry-run enabled. Skipping asset disk write.")
        return

    # 6. Write CSV
    print(f"[*] Writing {len(new_rows):,} records to {csv_dest}...")
    fieldnames = [
        "state",
        "city",
        "donor_hospital_code",
        "donor_hospital_name",
        "median_meld",
        "cohort_begin_date",
        "cohort_end_date",
    ]
    with open(csv_dest, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(new_rows)

    # 7. Write Coordinates JSON
    with open(coords_dest, "w") as f:
        json.dump(coords_map, f, indent=2)

    # 8. Write Manifest JSON
    manifest = {
        "cohort_version": cohort_version,
        "cohort_begin_date": begin_date,
        "cohort_end_date": end_date,
        "donor_hospital_count": len(new_rows),
        "manifest_url": "https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_manifest.json",
        "csv_url": "https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_data.csv",
        "coordinates_url": "https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_coordinates.json",
        "last_updated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    with open(manifest_dest, "w") as f:
        json.dump(manifest, f, indent=2)

    print("[✓] Successfully updated assets/mmat_data.csv")
    print("[✓] Successfully updated assets/mmat_coordinates.json")
    print("[✓] Successfully updated assets/mmat_manifest.json")
    print("\nNext: commit and push changes to origin/master so deployed apps sync automatically.")


if __name__ == "__main__":
    main()
