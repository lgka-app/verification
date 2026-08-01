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
