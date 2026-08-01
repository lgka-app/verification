// Golden generator for the web data layers: news, events, weather.
//
// Runs the app's REAL (vendored) service code fully offline: HTTP is served
// from fixtures via http.runWithClient + MockClient, and every
// non-deterministic input (today, referenceNow) is recorded in the golden's
// `params` so native runs are reproducible.
//
// Run:  flutter test test/generate_web_goldens_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:lgka_flutter/features/events/domain/event_model.dart';
import 'package:lgka_verification_harness/vendored/news_service_vendored.dart';
import 'package:lgka_verification_harness/vendored/events_service_vendored.dart';
import 'package:lgka_verification_harness/vendored/weather_service_vendored.dart';

const _encoder = JsonEncoder.withIndent('  ');

void _writeJson(String path, Object data) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync('${_encoder.convert(data)}\n');
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  setUpAll(() => tzdata.initializeTimeZones());
  final root = Directory.current.path;

  test('news fixtures -> news goldens', () async {
    final manifests = Directory('$root/fixtures/news')
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('manifest_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(manifests, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final mf in manifests) {
      final manifest = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
      final stamp = mf.uri.pathSegments.last
          .replaceAll('manifest_', '')
          .replaceAll('.json', '');

      final urlToFile = <String, String>{
        manifest['listUrl'] as String: manifest['listFile'] as String,
        for (final a in manifest['articles'] as List)
          (a as Map)['url'] as String: a['file'] as String,
      };

      final client = MockClient((request) async {
        final file = urlToFile[request.url.toString()];
        if (file == null) {
          return http.Response('not in fixture set', 404);
        }
        return http.Response.bytes(
          File('$root/fixtures/news/$file').readAsBytesSync(),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final events = await http.runWithClient(
        () => NewsService().fetchNewsEvents(forceRefresh: true),
        () => client,
      );

      _writeJson('$root/goldens/news/news_$stamp.json', {
        'input': {
          'manifest': 'fixtures/news/${mf.uri.pathSegments.last}',
          'sha256': _sha256(mf.readAsBytesSync()),
        },
        'expected': events
            .map((e) => {
                  ...e.toJson(),
                  'parsed_date': e.parsedDate?.toIso8601String(),
                })
            .toList(),
      });
    }
  });

  test('events fixtures -> events goldens', () {
    final manifests = Directory('$root/fixtures/events')
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('manifest_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(manifests, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final mf in manifests) {
      final manifest = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
      final stamp = mf.uri.pathSegments.last
          .replaceAll('manifest_', '')
          .replaceAll('.json', '');
      final todayStr = manifest['today'] as String;
      final tp = todayStr.split('-').map(int.parse).toList();
      final today = DateTime(tp[0], tp[1], tp[2]);

      // Aggregation mirror of EventsService.fetchUpcomingEvents (lines with
      // `seen` + sort): parse each week, dedup by (date, lowercased title),
      // sort ascending by date. Kept in sync with the app code by the golden
      // itself — if the app changes, regenerated goldens change.
      final all = <SchoolEvent>[];
      final seen = <String>{};
      for (final w in manifest['weeks'] as List) {
        final html =
            File('$root/fixtures/events/${(w as Map)['file']}').readAsStringSync();
        for (final event in harnessParseEventsWeekHtml(html, today)) {
          final key =
              '${event.date.toIso8601String()}|${event.title.toLowerCase().trim()}';
          if (seen.add(key)) all.add(event);
        }
      }
      all.sort((a, b) => a.date.compareTo(b.date));

      _writeJson('$root/goldens/events/events_$stamp.json', {
        'input': {
          'manifest': 'fixtures/events/${mf.uri.pathSegments.last}',
          'sha256': _sha256(mf.readAsBytesSync()),
        },
        'params': {'today': todayStr},
        'expected': all
            .map((e) => {
                  'date': e.date.toIso8601String(),
                  'time': e.time,
                  'title': e.title,
                })
            .toList(),
      });
    }
  });

  test('weather fixtures -> weather goldens', () async {
    final snapshots = Directory('$root/fixtures/weather')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(snapshots, isNotEmpty, reason: 'run tool/fetch_fixtures.sh first');

    for (final snap in snapshots) {
      final stamp = snap.uri.pathSegments.last
          .replaceAll('openmeteo_', '')
          .replaceAll('.json', '');
      final client = MockClient((request) async {
        if (request.url.host != 'api.open-meteo.com') {
          return http.Response('not in fixture set', 404);
        }
        return http.Response.bytes(snap.readAsBytesSync(), 200,
            headers: {'content-type': 'application/json'});
      });

      WeatherService.instance.invalidateCache();
      final result = await http.runWithClient(
        () => WeatherService.instance.fetchAll(),
        () => client,
      );

      // The hourly window is [now truncated to the hour, +24h). Record the
      // effective window start so native runs are reproducible; regenerate
      // weather goldens the same day the fixture was fetched.
      final referenceNow = result.hourly.isNotEmpty
          ? result.hourly.first.dt.toIso8601String()
          : DateTime.now().toIso8601String();

      _writeJson('$root/goldens/weather/weather_$stamp.json', {
        'input': {
          'file': 'fixtures/weather/${snap.uri.pathSegments.last}',
          'sha256': _sha256(snap.readAsBytesSync()),
        },
        'params': {'referenceNow': referenceNow},
        'expected': {
          'current': {
            'temp': result.current.temp,
            'feelsLike': result.current.feelsLike,
            'humidity': result.current.humidity,
            'windSpeed': result.current.windSpeed,
            'windDeg': result.current.windDeg,
            'windGust': result.current.windGust,
            'pressure': result.current.pressure,
            'clouds': result.current.clouds,
            'visibility': result.current.visibility,
            'uvi': result.current.uvi,
            'weatherCode': result.current.weatherCode,
            'isDay': result.current.isDay,
            'dt': result.current.dt.toIso8601String(),
          },
          'hourly': result.hourly
              .map((h) => {
                    'dt': h.dt.toIso8601String(),
                    'temp': h.temp,
                    'humidity': h.humidity,
                    'windSpeed': h.windSpeed,
                    'windDeg': h.windDeg,
                    'pop': h.pop,
                    'weatherCode': h.weatherCode,
                    'isDay': h.isDay,
                  })
              .toList(),
          'daily': result.daily
              .map((d) => {
                    'dt': d.dt.toIso8601String(),
                    'sunrise': d.sunrise.toIso8601String(),
                    'sunset': d.sunset.toIso8601String(),
                    'tempMax': d.tempMax,
                    'tempMin': d.tempMin,
                    'pop': d.pop,
                    'uvi': d.uvi,
                    'windSpeed': d.windSpeed,
                    'weatherCode': d.weatherCode,
                  })
              .toList(),
        },
      });
    }
  });
}
