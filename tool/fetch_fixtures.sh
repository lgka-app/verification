#!/bin/bash
# Downloads real inputs from the school website into fixtures/, stamped with
# the fetch date so multiple snapshots can accumulate over time (the more
# distinct real-world PDFs, the stronger the parity corpus).
# Credentials are the app's own public read-only ones (lib/config/app_credentials.dart).
set -euo pipefail

HARNESS="$(cd "$(dirname "$0")/.." && pwd)"
BASE=https://lessing-gymnasium-karlsruhe.de
AUTH="vertretungsplan:ephraim"
UA="LGKA+/harness"
STAMP=$(date +%Y-%m-%d)

fetch() { # url outfile
  curl -fsS -u "$AUTH" -A "$UA" "$1" -o "$2" && echo "fetched $2 ($(stat -f%z "$2") bytes)" || echo "FAILED: $1"
}

# Substitution plans (today / tomorrow)
fetch "$BASE/stundenplan/schueler/v_schueler_heute.pdf"  "$HARNESS/fixtures/substitution/heute_$STAMP.pdf"
fetch "$BASE/stundenplan/schueler/v_schueler_morgen.pdf" "$HARNESS/fixtures/substitution/morgen_$STAMP.pdf"

# Schedule page HTML (input to the link scraper)
fetch "$BASE/cm3/index.php/unterricht/stundenplan" "$HARNESS/fixtures/schedule/stundenplan_page_$STAMP.html"

# Schedule PDFs referenced by the page (grep hrefs like the app's parser targets)
grep -o 'href="[^"]*stundenplan[^"]*\.pdf"' "$HARNESS/fixtures/schedule/stundenplan_page_$STAMP.html" \
  | sed -e 's/^href="//' -e 's/"$//' | sort -u | while read -r href; do
  # normalize like the app does: /cm3/../X -> /X ; relative -> absolute
  url="$href"
  case "$url" in
    /cm3/../*) url="$BASE/${url#/cm3/../}" ;;
    /*)        url="$BASE$url" ;;
    http*)     ;;
    *)         url="$BASE/$url" ;;
  esac
  name=$(basename "$url" .pdf)
  fetch "$url" "$HARNESS/fixtures/schedule/${name}_$STAMP.pdf"
done

echo "---"
echo "fixture inventory:"
find "$HARNESS/fixtures" -type f | sort

# ── News: list page + every article on it + manifest ─────────────────────────
ND="$HARNESS/fixtures/news"; mkdir -p "$ND"
fetch "$BASE/cm3/index.php/neues" "$ND/list_$STAMP.html"
MANIFEST="$ND/manifest_$STAMP.json"
{
  printf '{\n  "fetchedAt": "%s",\n  "listUrl": "%s/cm3/index.php/neues",\n  "listFile": "list_%s.html",\n  "articles": [\n' "$STAMP" "$BASE" "$STAMP"
  first=1
  for href in $(grep -oE 'href="/cm3/index\.php/neues/[0-9]+-[^"]+"' "$ND/list_$STAMP.html" | sed -e 's/^href="//' -e 's/"$//' | sort -u); do
    slug=$(basename "$href")
    fetch "$BASE$href" "$ND/article_${slug}_$STAMP.html" >&2
    [ $first -eq 0 ] && printf ',\n'
    printf '    {"url": "%s%s", "file": "article_%s_%s.html"}' "$BASE" "$href" "$slug" "$STAMP"
    first=0
  done
  printf '\n  ]\n}\n'
} > "$MANIFEST"
echo "wrote $MANIFEST"

# ── Events: 3 week pages (today, +7d, +14d) + manifest ───────────────────────
ED="$HARNESS/fixtures/events"; mkdir -p "$ED"
EBASE="$BASE/cm3/index.php/termine/week.listevents"
{
  printf '{\n  "today": "%s",\n  "weeks": [\n' "$(date +%Y-%m-%d)"
  for w in 0 1 2; do
    dpath=$(date -v+$((w*7))d "+%Y/%m/%d")
    fetch "$EBASE/$dpath/-?catids=" "$ED/week${w}_$STAMP.html" >&2
    [ $w -gt 0 ] && printf ',\n'
    printf '    {"url": "%s/%s/-?catids=", "file": "week%s_%s.html"}' "$EBASE" "$dpath" "$w" "$STAMP"
  done
  printf '\n  ]\n}\n'
} > "$ED/manifest_$STAMP.json"
echo "wrote $ED/manifest_$STAMP.json"

# ── Weather: Open-Meteo snapshot (exact app query) ───────────────────────────
WD="$HARNESS/fixtures/weather"; mkdir -p "$WD"
WURL="https://api.open-meteo.com/v1/forecast?latitude=49.00775&longitude=8.375&elevation=122&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl,cloud_cover,visibility,uv_index,is_day&hourly=temperature_2m,relative_humidity_2m,weather_code,precipitation_probability,wind_speed_10m,wind_direction_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,wind_speed_10m_max,sunrise,sunset&timezone=Europe%2FBerlin&forecast_days=3"
curl -fsS "$WURL" -o "$WD/openmeteo_$STAMP.json" && echo "fetched $WD/openmeteo_$STAMP.json"
