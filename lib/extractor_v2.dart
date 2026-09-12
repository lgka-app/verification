// Substitution-plan extractor v2 — the reference implementation for the
// native rewrite. Unlike the shipping app's v1 (regex over flattened text,
// metadata only), v2 reconstructs the full Untis layout geometrically from
// word bounding boxes, which is the same approach PDFKit (iOS) and
// PdfBox-Android can implement.
//
// Untis plan shape (one page):
//   header : school / address (left), "SJ YYYY-YYYY" (center),
//            "Untis NNNN" + generation timestamp (right)
//   title  : "Lessing-Klassen D.M. / Weekday"
//   free announcement lines (optional)
//   "Abwesende Lehrer: A, B, C"   (optional)
//   "Abwesende Klassen: X, Y"     (optional)
//   table  : 10 columns — Art | Stunde | Klasse | Vertreter | Fach | Raum |
//            (Fach) | (Lehrer) | (Raum) | Text
//   footer : "Periode N  D.M.YYYY (week)  SJ YY/YY"

import 'package:syncfusion_flutter_pdf/pdf.dart';

const _weekdays = [
  'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
  'Freitag', 'Samstag', 'Sonntag',
];

/// Canonical column names, in visual order. `(Fach)`/`(Lehrer)`/`(Raum)` are
/// the ORIGINAL (cancelled) subject/teacher/room; the unparenthesized ones
/// are the replacements.
const columnNames = [
  'type',            // Art       (e.g. "Vertretung", "Entfall", "Veranst.", "Raumänderung")
  'period',          // Stunde    (e.g. "3", "1-11", "5-6")
  'classes',         // Klasse(n)
  'substitute',      // Vertreter
  'subject',         // Fach
  'room',            // Raum
  'originalSubject', // (Fach)
  'originalTeacher', // (Lehrer)
  'originalRoom',    // (Raum)
  'note',            // Text
];

class SubstitutionPlanV2 {
  String? school;
  String? address;
  String? schoolYear;
  String? untisVersion;
  String? generatedAt;
  String? planDate; // DD.MM.YYYY
  String? weekday; // German, capitalized
  bool isEmpty = false;
  List<String> announcements = [];
  List<String> absentTeachers = [];
  List<String> absentClasses = [];
  List<Map<String, dynamic>> entries = [];
  Map<String, dynamic> footer = {};

  Map<String, dynamic> toJson() => {
        'school': school,
        'address': address,
        'schoolYear': schoolYear,
        'untisVersion': untisVersion,
        'generatedAt': generatedAt,
        'planDate': planDate,
        'weekday': weekday,
        'isEmpty': isEmpty,
        'announcements': announcements,
        'absentTeachers': absentTeachers,
        'absentClasses': absentClasses,
        'entries': entries,
        'footer': footer,
      };

  /// All entries affecting [className] — matched against the expanded class
  /// list, so "6a" matches cells "6a", "6ab" and "5c, 6a".
  List<Map<String, dynamic>> entriesForClass(String className) {
    final lc = className.toLowerCase();
    return entries
        .where((e) =>
            (e['classes'] as List).any((c) => (c as String).toLowerCase() == lc))
        .toList();
  }
}

/// Expands an Untis class cell into individual classes:
/// "6ab" -> [6a, 6b]; "5a, 7c" -> [5a, 7c]; "J11" -> [J11].
List<String> _expandClasses(String cell) {
  final out = <String>[];
  for (final part in cell.split(',')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final m = RegExp(r'^(\d{1,2})([a-e]{2,})$').firstMatch(p);
    if (m != null) {
      for (final letter in m.group(2)!.split('')) {
        out.add('${m.group(1)}$letter');
      }
    } else {
      out.add(p);
    }
  }
  return out;
}

SubstitutionPlanV2 extractSubstitutionPlanV2(List<int> bytes) {
  final plan = SubstitutionPlanV2();
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final lines = PdfTextExtractor(doc)
        .extractTextLines(startPageIndex: 0, endPageIndex: 0);

    if (lines.map((l) => l.text.trim()).join().length < 50) {
      plan.isEmpty = true;
      return plan;
    }

    // ---- classify anchor lines -------------------------------------------
    int? titleIdx, teachersIdx, classesIdx, headerIdx, footerIdx;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].text.trim();
      if (titleIdx == null && t.contains('Klassen') && t.contains('/') &&
          _weekdays.any(t.contains)) {
        titleIdx = i;
      } else if (t.startsWith('Abwesende Lehrer')) {
        teachersIdx = i;
      } else if (t.startsWith('Abwesende Klassen')) {
        classesIdx = i;
      } else if (headerIdx == null &&
          t.startsWith('Art') &&
          t.contains('Stunde')) {
        headerIdx = i;
      } else if (RegExp(r'\d{1,2}\.\d{1,2}\.\d{4}\s*\(\d+\)')
          .hasMatch(t)) {
        // footer: "[Periode N]  D.M.YYYY (week)  SJ YY/YY" — the "Periode"
        // prefix exists in newer Untis exports only (e.g. 2027, not 2026)
        footerIdx = i;
      }
    }

    // ---- fixed header lines ----------------------------------------------
    for (var i = 0; i < (titleIdx ?? lines.length); i++) {
      final t = lines[i].text.trim();
      if (RegExp(r'^(SJ|Schuljahr) \d{4}-\d{4}$').hasMatch(t)) {
        plan.schoolYear = t;
      } else if (t.startsWith('Untis ')) {
        plan.untisVersion = t;
      } else if (RegExp(r'^\d{1,2}\.\d{1,2}\.\d{4}\s+\d{1,2}:\d{2}$')
          .hasMatch(t)) {
        plan.generatedAt = t.replaceAll(RegExp(r'\s+'), ' ');
      } else if (plan.school == null) {
        plan.school = t;
      } else if (plan.address == null) {
        plan.address = t;
      }
    }

    // ---- footer -----------------------------------------------------------
    String? footerYear;
    if (footerIdx != null) {
      final m = RegExp(
              r'(?:Periode\s+(\d+)\s+)?(\d{1,2})\.(\d{1,2})\.(\d{4})\s+\((\d+)\)(?:\s+SJ\s+(\S+))?')
          .firstMatch(lines[footerIdx].text.replaceAll(RegExp(r'\s+'), ' '));
      if (m != null) {
        footerYear = m.group(4);
        plan.footer = {
          'untisPeriod': m.group(1) == null ? null : int.parse(m.group(1)!),
          'date':
              '${m.group(2)!.padLeft(2, '0')}.${m.group(3)!.padLeft(2, '0')}.${m.group(4)}',
          'calendarWeek': int.parse(m.group(5)!),
          'schoolYearShort': m.group(6) == null ? null : 'SJ ${m.group(6)}',
        };
      }
    }

    // ---- title: partial date + weekday, year from footer ------------------
    if (titleIdx != null) {
      final m = RegExp(r'(\d{1,2})\.(\d{1,2})\.\s*/\s*(\w+)')
          .firstMatch(lines[titleIdx].text);
      if (m != null) {
        plan.weekday = m.group(3);
        if (footerYear != null) {
          plan.planDate =
              '${m.group(1)!.padLeft(2, '0')}.${m.group(2)!.padLeft(2, '0')}.$footerYear';
        }
      }
    }

    // ---- announcements: between title and first structural line -----------
    final annEnd = [teachersIdx, classesIdx, headerIdx, footerIdx, lines.length]
        .whereType<int>()
        .reduce((a, b) => a < b ? a : b);
    if (titleIdx != null) {
      for (var i = titleIdx + 1; i < annEnd; i++) {
        final t = lines[i].text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) plan.announcements.add(t);
      }
    }

    // ---- absences ---------------------------------------------------------
    List<String> valuesAfterColon(TextLine line) {
      final colon = line.text.indexOf(':');
      if (colon < 0) return [];
      return line.text
          .substring(colon + 1)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    if (teachersIdx != null) {
      plan.absentTeachers = valuesAfterColon(lines[teachersIdx]);
    }
    if (classesIdx != null) {
      plan.absentClasses = valuesAfterColon(lines[classesIdx]);
    }

    // ---- table ------------------------------------------------------------
    if (headerIdx != null) {
      // Column x-starts from header words. Exports split header words by
      // kerning ("T ext") or even per glyph ("A r t" in Untis 2026); such
      // fragments continue at ~0px from the previous fragment's right edge
      // (often overlapping), while genuine neighboring columns sit >=5px
      // apart — so anything closer than 3px is the same word.
      final xs = <double>[];
      double? lastRight;
      for (final w in lines[headerIdx].wordCollection) {
        if (w.text.trim().isEmpty) continue;
        if (xs.isEmpty || w.bounds.left - lastRight! > 3) {
          xs.add(w.bounds.left);
        }
        lastRight = w.bounds.right;
      }
      if (xs.length != columnNames.length) {
        throw StateError(
            'expected ${columnNames.length} columns, found ${xs.length}: $xs');
      }

      int columnOf(double left) {
        for (var c = xs.length - 1; c >= 0; c--) {
          if (left >= xs[c] - 3) return c;
        }
        return 0;
      }

      final tableEnd = footerIdx ?? lines.length;
      Map<String, dynamic>? current;
      for (var i = headerIdx + 1; i < tableEnd; i++) {
        final cells = List<String>.filled(columnNames.length, '');
        int? prevCol;
        double? prevRight;
        for (final w in lines[i].wordCollection) {
          final t = w.text.trim();
          if (t.isEmpty) continue;
          final c = columnOf(w.bounds.left);
          if (cells[c].isEmpty) {
            cells[c] = t;
          } else if (c == prevCol && w.bounds.left - prevRight! <= 3) {
            cells[c] = '${cells[c]}$t'; // glyph fragment of the same word
          } else {
            cells[c] = '${cells[c]} $t';
          }
          prevCol = c;
          prevRight = w.bounds.right;
        }
        if (cells.every((c) => c.isEmpty)) continue;

        final isNewEntry = cells[0].isNotEmpty || cells[1].isNotEmpty;
        if (isNewEntry) {
          current = {
            for (var c = 0; c < columnNames.length; c++)
              columnNames[c]: cells[c].isEmpty ? null : cells[c],
          };
          current['classesRaw'] = cells[2].isEmpty ? null : cells[2];
          current['classes'] = _expandClasses(cells[2]);
          plan.entries.add(current);
        } else if (current != null) {
          // continuation line: append wrapped cell text
          for (var c = 0; c < columnNames.length; c++) {
            if (cells[c].isEmpty || columnNames[c] == 'classes') continue;
            final prev = current[columnNames[c]];
            current[columnNames[c]] =
                prev == null ? cells[c] : '$prev ${cells[c]}';
          }
        }
      }
    }

    return plan;
  } finally {
    doc.dispose();
  }
}
