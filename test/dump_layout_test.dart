// Diagnostic: dump per-line/per-word geometry of the substitution PDFs so we
// can design the full structured extractor (v2) from the real Untis layout.
// Run:  flutter test test/dump_layout_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('dump substitution PDF layout', () {
    final root = Directory.current.path;
    final pdfs = Directory('$root/fixtures/substitution')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final pdf in pdfs) {
      final doc = PdfDocument(inputBytes: pdf.readAsBytesSync());
      final out = StringBuffer();
      out.writeln('==== ${pdf.uri.pathSegments.last} '
          '(${doc.pages.count} page(s)) ====');
      final lines = PdfTextExtractor(doc).extractTextLines();
      for (final line in lines) {
        out.writeln('LINE y=${line.bounds.top.toStringAsFixed(1)} '
            'x=${line.bounds.left.toStringAsFixed(1)} '
            '"${line.text}"');
        for (final word in line.wordCollection) {
          out.writeln('  w x=${word.bounds.left.toStringAsFixed(1)}-'
              '${word.bounds.right.toStringAsFixed(1)} '
              '"${word.text}"');
        }
      }
      doc.dispose();
      final name = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
      File('$root/goldens/substitution/$name.layout.txt')
          .writeAsStringSync(out.toString());
    }
  });
}
