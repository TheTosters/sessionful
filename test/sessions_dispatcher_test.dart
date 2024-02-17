import 'dart:math';
import 'dart:typed_data';

import 'package:sessionful/sessionful.dart';
import 'package:sessionful/src/session.dart';
import 'package:test/test.dart';

class _DummySink implements Sink<Uint8List> {
  final List<Uint8List> items = [];
  final List<Session> sessions = [];
  final List<Session> terminatedSessions = [];

  void onNewSession(Session s) => sessions.add(s);

  void onSessionTerminate(Session s) => terminatedSessions.add(s);

  @override
  void add(Uint8List data) => items.add(data);

  @override
  void close() {}
}

Uint8List intAsData(int i) {
  ByteData data = ByteData(4);
  data.setInt32(0, i);
  return data.buffer.asUint8List();
}

Uint8List _buildStreamFromMap(Map<int, List<int>> trafficMap) {
  final sink = _DummySink();
  for (final MapEntry(key: sessionId, value: sessionData) in trafficMap.entries) {
    final session = SessionBuilder.create(sessionId, sink, 86);
    final sessionPayload = sessionData.map((e) => intAsData(e)).toList();
    session.push(sessionPayload);
  }
  UnboundBuffersCombiner combiner = UnboundBuffersCombiner(sink.items.first);
  sink.items.removeAt(0);
  for (final d in sink.items) {
    combiner.add(d);
  }
  return combiner.getCombined();
}

Future<void> _verifySessions(List<Session> sessions, Map<int, List<int>> sessionsTrafficMap) async {
  expect(sessions.length, sessionsTrafficMap.keys.length);
  for (final session in sessions) {
    final payload = await session.pull();
    final dataAccess = ByteData.view(payload.buffer);
    final itemsCount = payload.length ~/ 4;
    final payloadItems = <int>[];
    for (int t = 0; t < itemsCount; t++) {
      payloadItems.add(dataAccess.getInt32(t * 4));
    }
    expect(sessionsTrafficMap[session.sessionId], payloadItems);
  }
}

void _sendWithFragmentation(Uint8List inputData, SessionsDispatcher dispatcher, int randSeed,
    {int minChunkSize = 1, int maxChunkSize = 4}) {
  final r = Random(randSeed);
  int offset = 0;
  int size = inputData.length;
  while (size > 0) {
    var chunkSize = minChunkSize + r.nextInt(maxChunkSize - minChunkSize);
    if (chunkSize > size) {
      chunkSize = size;
    }
    final chunk = inputData.sublist(offset, offset + chunkSize);
    size -= chunkSize;
    offset += chunkSize;
    dispatcher.add(chunk);
  }
}

class _Action {
  final int sessionId;
  final List<int>? inputData;
  final bool terminate;

  _Action.send(this.sessionId, this.inputData) : terminate = false;

  _Action.terminate(this.sessionId)
      : terminate = true,
        inputData = null;

  void perform(Sink<Uint8List> sink) {
    final session = SessionBuilder.create(sessionId, sink, 86);
    if (terminate) {
      session.sendTermination();
    } else {
      final sessionPayload = inputData!.map((e) => intAsData(e)).toList();
      session.push(sessionPayload);
    }
  }
}

Uint8List _buildStreamFromActions(List<_Action> actions) {
  final sink = _DummySink();
  for (final a in actions) {
    a.perform(sink);
  }
  UnboundBuffersCombiner combiner = UnboundBuffersCombiner(sink.items.first);
  sink.items.removeAt(0);
  for (final d in sink.items) {
    combiner.add(d);
  }
  return combiner.getCombined();
}

void main() {
  group('Sessions Dispatcher test', () {
    test('Check fragmented data', () async {
      final sink = _DummySink();
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 82,
      );
      final inputData =
          Uint8List.fromList([82, 0, 0, 0, 1, 0, 0, 0, 8, 0, 12, 180, 234, 0, 0, 15, 34]);
      _sendWithFragmentation(inputData, dispatcher, 345564);
      expect(sink.sessions.length, 1);
      final payload = sink.sessions.first.maybePull();
      expect(payload, isNotNull);
      final data = ByteData.view(payload!.buffer);
      expect(data.getInt32(0), 832746);
      expect(data.getInt32(4), 3874);
    });
    test('Detect sessions', () async {
      final sink = _DummySink();
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 82,
      );
      final ses1 = Uint8List.fromList([82, 0, 0, 0, 1, 0, 0, 0, 8, 0, 12, 180, 234, 0, 0, 15, 34]);
      final ses2 = Uint8List.fromList([82, 0, 0, 1, 1, 0, 0, 0, 8, 0, 12, 180, 234, 0, 0, 15, 34]);
      dispatcher.add(ses1);
      dispatcher.add(ses2);
      expect(sink.sessions.length, 2);
    });

    test('Dispatch traffic', () async {
      final sink = _DummySink();
      //Build traffic
      final sessionsTrafficMap = {
        22: [34543, 1232],
        532: [112],
        98: [123, 345, 67, 123]
      };
      final inputPayload = _buildStreamFromMap(sessionsTrafficMap);
      //forward traffic to dispatcher
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 86,
      );
      dispatcher.add(inputPayload);
      await _verifySessions(sink.sessions, sessionsTrafficMap);
    });

    test('Dispatch traffic with fragmentation', () async {
      final sink = _DummySink();
      //Build traffic
      final sessionsTrafficMap = {
        122: [34543, 1232],
        5232: [112, 44],
        918: [123, 345, 67, 123, 23]
      };
      final inputPayload = _buildStreamFromMap(sessionsTrafficMap);
      //forward traffic to dispatcher
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 86,
      );
      _sendWithFragmentation(inputPayload, dispatcher, 678);
      await _verifySessions(sink.sessions, sessionsTrafficMap);
    });

    test('Dispatch traffic with fragmentation (large chunks)', () async {
      final sink = _DummySink();
      //Build traffic
      final sessionsTrafficMap = {
        122: [34543, 1232, 324, 13221, 45, 234, 435],
        5232: [112, 44, 34, 234],
        918: [123, 345, 67, 123, 23, 1221, 1, 21],
      };
      final inputPayload = _buildStreamFromMap(sessionsTrafficMap);
      //forward traffic to dispatcher
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 86,
      );
      _sendWithFragmentation(inputPayload, dispatcher, 6782, minChunkSize: 15, maxChunkSize: 25);
      await _verifySessions(sink.sessions, sessionsTrafficMap);
    });

    test('Dispatch traffic with session termination', () async {
      //Build traffic
      final actions1 = <_Action>[
        _Action.send(5232, [112, 44, 34, 234]),
        _Action.send(122, [34543, 1232, 324, 13221, 45, 234, 435]),
        _Action.send(918, [123, 345, 67, 123, 23, 1221, 1, 21]),
      ];
      final actions2 = <_Action>[
        _Action.terminate(122),
        _Action.send(5232, [112, 44, 34, 234]),
        _Action.terminate(5232),
        _Action.send(122, [34543, 1232, 324, 13221, 45, 234, 435]),
        _Action.send(918, [22, 22]),
      ];
      final inputPayload = _buildStreamFromActions(actions1);
      final inputPayload2 = _buildStreamFromActions(actions2);

      //forward traffic to dispatcher
      final sink = _DummySink();
      final dispatcher = SessionsDispatcher(
        outputSink: sink,
        onNewSessionDiscovered: sink.onNewSession,
        onSessionTerminated: sink.onSessionTerminate,
        sessionMarker: 86,
      );
      dispatcher.add(inputPayload);
      dispatcher.add(inputPayload2);
      expect(sink.terminatedSessions.length, 2);
      expect(sink.terminatedSessions[0].sessionId, 122);
      expect(sink.terminatedSessions[1].sessionId, 5232);

      expect(sink.sessions.length, 4); // 122, 5232, 918 + recreated 122
    });
  });
}
