import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/live.dart';
import 'package:tuitiontrack/core/push.dart';

void main() {
  test('the live connection follows the server address', () {
    expect(LiveConnection.socketUri('https://tuitiontrack-api.onrender.com').toString(), 'wss://tuitiontrack-api.onrender.com/ws/');
    expect(LiveConnection.socketUri('http://192.168.0.5:8000').toString(), 'ws://192.168.0.5:8000/ws/');
  });

  test('events from push reach the same listeners', () async {
    final got = <String>[];
    final sub = LiveConnection.instance.events.listen((e) => got.add(e['type'] as String));
    LiveConnection.instance.emit({'type': 'nudge'});
    await Future<void>.delayed(Duration.zero);
    expect(got, ['nudge']);
    await sub.cancel();
  });

  test('a build without a Firebase project has no push, and nothing breaks', () {
    expect(Push.configured, isFalse);
    expect(Push.ready, isFalse);
  });
}
