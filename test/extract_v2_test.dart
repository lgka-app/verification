// Runs extractor v2 over the substitution fixtures, writes full-structure
// goldens (*.v2.json), and prints the per-class view for a sample class.
// Run:  flutter test test/extract_v2_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lgka_verification_harness/extractor_v2.dart';

const _encoder = JsonEncoder.withIndent('  ');

void main() {
  test('substitution PDFs -> full v2 goldens', () {
    final root = Directory.current.path;
    final pdfs = Directory('$root/fixtures/substitution')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(pdfs, isNotEmpty);

    for (final pdf in pdfs) {
      final bytes = pdf.readAsBytesSync();
      final name = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
      final plan = extractSubstitutionPlanV2(bytes);

      File('$root/goldens/substitution/$name.v2.json').writeAsStringSync(
          '${_encoder.convert({
            'input': {
              'file': 'fixtures/substitution/${pdf.uri.pathSegments.last}',
              'sha256': sha256.convert(bytes).toString(),
              'bytes': bytes.length,
            },
            'expected': plan.toJson(),
          })}\n');

      // Demonstrate the per-class query for a few classes.
      for (final cls in ['10b', 'J12', '7b']) {
        // ignore: avoid_print
        print('$name  entriesForClass($cls): '
            '${jsonEncode(plan.entriesForClass(cls))}');
      }
    }
  });
}
