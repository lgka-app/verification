// Golden-dataset generator for the LGKA+ native rewrite.
//
// Runs the app's REAL Dart extraction code (vendored verbatim via
// tool/sync_sources.sh) over every fixture in fixtures/ and writes
// language-neutral JSON goldens to goldens/. The Swift and Kotlin
// extractors must reproduce these outputs byte-for-byte (semantically —
// same JSON values) from the same fixture inputs.
//
// Run:  flutter test test/generate_goldens_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

import 'package:lgka_verification_harness/vendored/substitution_service_vendored.dart'
    show harnessExtractSubstitutionMetadata;
import 'package:lgka_verification_harness/vendored/schedule_service_vendored.dart'
    show harnessParseScheduleHtml;
import 'package:lgka_verification_harness/vendored/schedule_provider_vendored.dart'
    show harnessBuildClassIndex;

const _encoder = JsonEncoder.withIndent('  ');

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

void _writeJson(String path, Object data) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync('${_encoder.convert(data)}\n');
}

/// Raw, UNNORMALIZED Syncfusion text — diagnostic only, not part of the
/// parity contract (each platform's PDF library emits different raw text).
String _rawText(List<int> bytes, {int? pageIndex}) {
  final doc = syncfusion.PdfDocument(inputBytes: bytes);
  try {
    final extractor = syncfusion.PdfTextExtractor(doc);
    if (pageIndex != null) {
      return extractor.extractText(
          startPageIndex: pageIndex, endPageIndex: pageIndex);
    }
    return extractor.extractText();
  } finally {
    doc.dispose();
  }
}

int _pageCount(List<int> bytes) {
  final doc = syncfusion.PdfDocument(inputBytes: bytes);
  try {
    return doc.pages.count;
  } finally {
    doc.dispose();
  }
}

void main() {
  final root = Directory.current.path;
  final subFixtures = Directory('$root/fixtures/substitution');
  final schedFixtures = Directory('$root/fixtures/schedule');

  test('substitution PDFs -> metadata goldens', () {
    final pdfs = subFixtures
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(pdfs, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final pdf in pdfs) {
      final bytes = pdf.readAsBytesSync();
      final name = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
      final result = harnessExtractSubstitutionMetadata(bytes);

      _writeJson('$root/goldens/substitution/$name.json', {
        'input': {
          'file': 'fixtures/substitution/${pdf.uri.pathSegments.last}',
          'sha256': _sha256(bytes),
          'bytes': bytes.length,
        },
        'expected': {
          'weekday': result['weekday'],
          'date': result['date'],
          'lastUpdated': result['lastUpdated'],
        },
      });

      File('$root/goldens/substitution/$name.rawtext.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync(_rawText(bytes, pageIndex: 0));
    }
  });

  test('schedule page HTML -> schedule item goldens', () {
    final pages = schedFixtures
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(pages, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final page in pages) {
      final content = page.readAsStringSync();
      final name = page.uri.pathSegments.last.replaceAll('.html', '');
      final items = harnessParseScheduleHtml(content);

      _writeJson('$root/goldens/schedule/$name.json', {
        'input': {
          'file': 'fixtures/schedule/${page.uri.pathSegments.last}',
          'sha256': _sha256(utf8.encode(content)),
        },
        'expected': items
            .map((s) => {
                  'title': s.title,
                  'url': s.url,
                  'halbjahr': s.halbjahr,
                  'gradeLevel': s.gradeLevel,
                  'fullUrl': s.fullUrl,
                })
            .toList(),
      });
    }
  });

  test('schedule PDFs -> class index goldens', () async {
    final pdfs = schedFixtures
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(pdfs, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final pdf in pdfs) {
      final bytes = pdf.readAsBytesSync();
      final name = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
      final index = await harnessBuildClassIndex(pdf.path);
      final sortedIndex = Map.fromEntries(
          index.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

      _writeJson('$root/goldens/schedule/class_index_$name.json', {
        'input': {
          'file': 'fixtures/schedule/${pdf.uri.pathSegments.last}',
          'sha256': _sha256(bytes),
          'bytes': bytes.length,
          'pageCount': _pageCount(bytes),
        },
        // classIndexJ11J12 is a hardcoded constant in the app, not parsed:
        // {'j11': 2, 'j12': 3} — replicate as a constant, don't parse for it.
        'expected': {'classIndex5to10': sortedIndex},
      });
    }
  });

  test('write manifest', () async {
    final appCommit = (await Process.run('git',
            ['-C', '/Users/luka/Documents/lgka-app', 'rev-parse', 'HEAD']))
        .stdout
        .toString()
        .trim();
    final flutterVersion =
        (await Process.run('flutter', ['--version', '--machine'])).stdout;

    _writeJson('$root/goldens/manifest.json', {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'appRepo': 'https://github.com/luka-loehr/LGKA',
      'appCommit': appCommit,
      'extractor': 'syncfusion_flutter_pdf (see pubspec.lock for version)',
      'flutter': jsonDecode(flutterVersion.toString()),
      'contract': {
        'substitution':
            'metadata extraction from page 0: weekday (German, capitalized; '
                '"weekend" sentinel when text < 50 chars), date (DD.MM.YYYY), '
                'lastUpdated (D.M.YYYY HH:MM as printed in the PDF)',
        'scheduleHtml':
            'anchor scrape of #mod-custom213 a[href*=stundenplan]: title, '
                'href, halbjahr (from hj1/hj2 in href), gradeLevel, absolute URL',
        'classIndex':
            'lowercased page text scan, classes 5a-10e, first page containing '
                'the class string wins, stored page number is pageIndex + 2 '
                '(1-based + cover offset); j11/j12 constant {j11:2, j12:3}',
        'note': 'rawtext.txt files are Syncfusion diagnostics, NOT normative — '
            'native extractors emit different raw text and must only match '
            'the expected JSON values',
      },
    });
  });
}
