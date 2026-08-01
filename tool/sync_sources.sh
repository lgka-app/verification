#!/bin/bash
# Vendors the LGKA+ app's parser sources into the harness so the goldens are
# produced by the EXACT code the Flutter app ships. Re-run whenever the app's
# parsers change — never edit lib/vendored/ by hand.
#
# For each source file we:
#   1. copy it verbatim from the app repo
#   2. rewrite its relative imports to package:lgka_flutter/ imports
#   3. append a public shim so the harness can call the library-private
#      parse function without modifying the original code
set -euo pipefail

APP=/Users/luka/Documents/lgka-app/lib
OUT="$(cd "$(dirname "$0")/.." && pwd)/lib/vendored"
mkdir -p "$OUT"

# --- substitution_service.dart (lives in lib/features/substitution/data/) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/substitution/domain/|" \
  -e "s|import '\.\./\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/substitution/data/substitution_service.dart" > "$OUT/substitution_service_vendored.dart"
cat >> "$OUT/substitution_service_vendored.dart" <<'EOF'

// ---- harness shim (appended by tool/sync_sources.sh) ----
Map<String, String> harnessExtractSubstitutionMetadata(List<int> bytes) =>
    _extractPdfData(bytes);
EOF

# --- schedule_service.dart (lives in lib/features/schedule/data/) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/schedule/domain/|" \
  -e "s|import '\.\./\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/schedule/data/schedule_service.dart" > "$OUT/schedule_service_vendored.dart"
cat >> "$OUT/schedule_service_vendored.dart" <<'EOF'

// ---- harness shim (appended by tool/sync_sources.sh) ----
List<ScheduleItem> harnessParseScheduleHtml(String htmlContent) =>
    _parseScheduleHtml(htmlContent);
EOF

# --- schedule_provider.dart (lives in lib/features/schedule/application/) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/schedule/domain/|" \
  -e "s|import '\.\./data/|import 'package:lgka_flutter/features/schedule/data/|" \
  -e "s|import '\.\./\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/schedule/application/schedule_provider.dart" > "$OUT/schedule_provider_vendored.dart"
cat >> "$OUT/schedule_provider_vendored.dart" <<'EOF'

// ---- harness shim (appended by tool/sync_sources.sh) ----
Future<Map<String, int>> harnessBuildClassIndex(String pdfPath) =>
    _buildClassIndexInIsolate(pdfPath);
EOF

echo "Vendored 3 sources into $OUT"

# --- news_service.dart (lives in lib/features/news/data/) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/news/domain/|" \
  -e "s|import '\.\./\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/news/data/news_service.dart" > "$OUT/news_service_vendored.dart"

# --- events_service.dart (lives in lib/features/events/data/ — NOTE: only 3 levels up to utils) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/events/domain/|" \
  -e "s|import '\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/events/data/events_service.dart" > "$OUT/events_service_vendored.dart"
cat >> "$OUT/events_service_vendored.dart" <<'SHIM'

// ---- harness shim (appended by tool/sync_sources.sh) ----
List<SchoolEvent> harnessParseEventsWeekHtml(String html, DateTime today) =>
    EventsService.instance._parseWeekHtml(html, today);
SHIM

# --- weather_service.dart (lives in lib/features/weather/data/) ---
sed \
  -e "s|import '\.\./domain/|import 'package:lgka_flutter/features/weather/domain/|" \
  -e "s|import '\.\./\.\./\.\./\.\./|import 'package:lgka_flutter/|" \
  "$APP/features/weather/data/weather_service.dart" > "$OUT/weather_service_vendored.dart"

echo "Vendored web services (news, events, weather)"
