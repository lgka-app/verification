> **Moved (2026-09-12).** The parity harness now lives in [lgka-app/api](https://github.com/lgka-app/api):
> fixtures and goldens under `test/`, the Rust comparator under `tool/compare-report`, and `npm run parity`
> renders the report against the API's parsers (21/21 at strict equality). The native apps no longer contain
> extractors — they consume https://api.lgka.app. This repository is kept for history and is no longer updated.

# LGKA+ Verification Harness

Golden-dataset generator for the native rewrite ([lgka-app/lgka-ios](https://github.com/lgka-app/lgka-ios), [lgka-app/lgka-android](https://github.com/lgka-app/lgka-android)).

It runs the **real Dart extraction code of the shipping Flutter app** ([luka-loehr/LGKA](https://github.com/luka-loehr/LGKA)) over **real PDFs/HTML from the school server** and writes language-neutral JSON goldens. The Swift and Kotlin extractors are correct when, given the same fixture bytes, they produce the same `expected` JSON values.

## Layout

```
tool/sync_sources.sh    vendors the app's parser sources (verbatim copy +
                        import rewrite + public shim). Re-run after any
                        parser change in the app. Never edit lib/vendored/.
tool/fetch_fixtures.sh  downloads today's real inputs, date-stamped
fixtures/               inputs (PDFs, HTML) — accumulate over time!
goldens/                outputs — the parity contract
test/                   the generator (flutter test)
```

## Setup

Clone the Flutter app as a **sibling directory named `LGKA`** (the pubspec
path-depends on `../LGKA`):

```bash
git clone https://github.com/luka-loehr/LGKA.git ../LGKA
```

## Run

```bash
./tool/sync_sources.sh      # refresh vendored app code
./tool/fetch_fixtures.sh    # snapshot today's real data (additive)
flutter pub get
flutter test test/generate_goldens_test.dart      # substitution + schedule
flutter test test/generate_web_goldens_test.dart  # news + events + weather
```

## The contract (what native extractors must reproduce)

| Golden | From | Expected output |
|---|---|---|
| `goldens/substitution/*.json` | substitution PDF page 0 | `weekday` (German, capitalized; `"weekend"` if page text < 50 chars), `date` (`DD.MM.YYYY`), `lastUpdated` (timestamp as printed, e.g. `27.7.2026 13:08`) |
| `goldens/schedule/stundenplan_page_*.json` | schedule page HTML | ordered list of `{title, url, halbjahr, gradeLevel, fullUrl}` from `#mod-custom213 a[href*=stundenplan]`, deduped by fullUrl |
| `goldens/schedule/class_index_*.json` | schedule PDF | map class → page for `5a`–`10e`: first page (lowercased text scan) containing the class string, stored as `pageIndex + 2`. `j11`/`j12` are a hardcoded constant `{j11: 2, j12: 3}`, never parsed |
| `goldens/news/news_*.json` | news list page + article pages (manifest-mapped) | full `NewsEvent.toJson()` list, newest-first by `parsed_date` (undated keep list order): metadata, plain `content`, serialized `html_content`, embedded vs standalone links, gallery + inline images, downloads with file type/size, tags |
| `goldens/events/events_*.json` | JEvents week-list pages + `params.today` | `{date, time, title}` list: regex scrape of `ev_td_li` items, date from `icalrepeat.detail` href, past-vs-today filtered, deduped by (date, lowercased title), sorted ascending |
| `goldens/weather/weather_*.json` | Open-Meteo snapshot + `params.referenceNow` | `current` / `hourly` (window `[referenceNow, +24h)`) / `daily` mapped exactly like `WeatherService.fetchAll` (Dart `toIso8601String` timestamps, `pop` scaled to 0–1, `pressure` rounded) |

## Native implementations

Both native extractors are verified against these goldens at 100% parity:

- **Kotlin** (PDFBox): [`lgka-app/lgka-android`](https://github.com/lgka-app/lgka-android) → `extractor/`
- **Swift** (PDFKit): [`lgka-app/lgka-ios`](https://github.com/lgka-app/lgka-ios) → `Sources/LGKAExtractor`

Each ships a runner CLI (`<substitution|classindex> <fixturesDir> <outDir>`)
covering both the substitution extractor and the schedule class-to-page index
(all class_index goldens gated too). Compare outputs with the
Rust comparator — run once, get `report.html`:

```bash
cargo run --release --manifest-path tool/compare-report/Cargo.toml -- \
  <kotlin-out-dir> --swift <swift-out-dir> --out report.html
```

Exit code 0 only on full parity — usable as a CI gate. Port lessons learned
(all handled by both ports): Syncfusion doubles glyphs in flat text; older
Untis exports split words per glyph (join fragments touching within 3px);
PDFKit `characterBounds(at:)` indexes text without the newlines present in
`page.string` (track the bounds index separately) and returns tight glyph
bounds (cluster lines via `selectionsByLine()` bands, not glyph tops); footer
"Periode" prefix exists only in newer Untis exports.

## Caveats

- **`*.rawtext.txt` is diagnostic, not normative.** Syncfusion's raw extraction has quirks (e.g. doubled glyphs: "Gyymnasium") that PDFKit/PdfBox will not reproduce. Native parsers must match the *parsed JSON*, not the raw text. Expect to re-tune regexes per platform.
- **Year fallback nondeterminism.** The substitution parser falls back to `DateTime.now().year` when no year is found anywhere in the PDF. All current fixtures contain a footer/timestamp year, so goldens are stable — but regenerating goldens years later could differ for a hypothetical year-less PDF.
- **Grow the corpus.** Run `tool/fetch_fixtures.sh` on different school days (normal days, exam weeks, first/last day of term, days with many cancellations) — fixtures are date-stamped and additive. The current snapshot (2026-08-01, summer holidays) captured the last school day's plan.
- Fixtures are fetched with the app's own public read-only credentials (`lib/config/app_credentials.dart`).
- **Weather goldens must be regenerated the same day their fixture was fetched** — the hourly window is anchored to generation time; `params.referenceNow` records the window start for native runs (`weather` mode takes it as an extra CLI arg).
- **Events goldens are parameterized by `params.today`** (past-event filtering); the extra `manifest_sept-week_*` fixture covers a populated school week during term time.
- **Captured app bug (intentional):** the live site prints creation dates as `28. Juli 2026`, but the app's parser expects `DD.MM.YYYY` — so `parsed_date` is null on every current article and news keeps list order. The goldens capture the app's real behavior; fix it in the app first if you want it fixed in the ports.
- The Dart-side `dependency_overrides` for `weather_icons` (vendored under `third_party/`) is required because pub ignores the app's own overrides when the app is consumed as a path dependency.
