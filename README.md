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
flutter test test/generate_goldens_test.dart
```

## The contract (what native extractors must reproduce)

| Golden | From | Expected output |
|---|---|---|
| `goldens/substitution/*.json` | substitution PDF page 0 | `weekday` (German, capitalized; `"weekend"` if page text < 50 chars), `date` (`DD.MM.YYYY`), `lastUpdated` (timestamp as printed, e.g. `27.7.2026 13:08`) |
| `goldens/schedule/stundenplan_page_*.json` | schedule page HTML | ordered list of `{title, url, halbjahr, gradeLevel, fullUrl}` from `#mod-custom213 a[href*=stundenplan]`, deduped by fullUrl |
| `goldens/schedule/class_index_*.json` | schedule PDF | map class → page for `5a`–`10e`: first page (lowercased text scan) containing the class string, stored as `pageIndex + 2`. `j11`/`j12` are a hardcoded constant `{j11: 2, j12: 3}`, never parsed |

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
