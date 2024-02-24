import 'dart:typed_data';

import 'package:sessionful/src/session.dart';
import 'package:test/test.dart';

class _DummySink implements Sink<Uint8List> {
  final List<Uint8List> items = [];

  @override
  void add(Uint8List data) => items.add(data);

  @override
  void close() {}
}

class _ForwardingSink implements Sink<Uint8List> {
  final List<Uint8List> items = [];
  Session? destination;
  final int itemsCount;

  _ForwardingSink(this.itemsCount);

  @override
  void add(Uint8List data) {
    items.add(data);
    if (items.length == itemsCount) {
      for (final f in items) {
        expect(destination!.consumePayload(f), f.length);
      }
    }
  }

  @override
  void close() {}
}

Uint8List intAsData(int i) {
  ByteData data = ByteData(4);
  data.setInt32(0, i);
  return data.buffer.asUint8List();
}

void main() {
  group('Session test', () {
    test('Check Push single item', () {
      final sink = _DummySink();
      final session = SessionBuilder.create(1111, sink, 82);
      session.push([intAsData(832746)]);
      for (final f in sink.items) {
        expect(session.consumePayload(f), f.length);
      }
      final payload = session.maybePull();
      expect(payload, isNotNull);
      final data = ByteData.view(payload!.buffer);
      expect(data.getInt32(0), 832746);
    });

    test('Check Push multiple items', () {
      final sink = _DummySink();
      final session = SessionBuilder.create(1, sink, 82);
      session.push([intAsData(832746), intAsData(3874)]);
      for (final f in sink.items) {
        expect(session.consumePayload(f), f.length);
      }
      final payload = session.maybePull();
      expect(payload, isNotNull);
      final data = ByteData.view(payload!.buffer);
      expect(data.getInt32(0), 832746);
      expect(data.getInt32(4), 3874);
    });

    test('Check maybePull with no data', () {
      final session = SessionBuilder.create(1, _DummySink(), 82);
      expect(session.maybePull(), isNull);
    });

    test('Check maybePull with data', () {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);
      session.push([intAsData(832746)]);

      //New session object
      session = SessionBuilder.create(1, sink, 82);
      for (final f in sink.items) {
        expect(session.consumePayload(f), f.length);
      }
      expect(session.maybePull(), isNotNull);
      expect(session.maybePull(), isNull);
    });

    test('Check pull with data', () async {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);
      session.push([intAsData(832746)]);

      //New session object
      session = SessionBuilder.create(1, sink, 82);
      for (final f in sink.items) {
        expect(session.consumePayload(f), f.length);
      }
      expect(await session.pull(), isNotNull);
    });

    test('Check pull with waiting for data', () async {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);
      session.push([intAsData(832746)]);

      //New session object
      session = SessionBuilder.create(1, sink, 82);
      Future.delayed(Duration(milliseconds: 100), () {
        for (final f in sink.items) {
          expect(session.consumePayload(f), f.length);
        }
      });
      expect(await session.pull(), isNotNull);
    });

    test('Check pushPull', () async {
      final sink = _ForwardingSink(2);
      final session = SessionBuilder.create(1, sink, 82);
      sink.destination = session;
      final payload = await session.pushPull([intAsData(832746)]);
      final data = ByteData.view(payload.buffer);
      expect(data.getInt32(0), 832746);
    });

    test('Check session termination', () async {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);
      session.sendTermination();
      expect(session.isTerminated, true);

      //Create new object and check behavior
      session = SessionBuilder.create(1, sink, 82);
      for (final f in sink.items) {
        expect(session.consumePayload(f), f.length);
      }
      expect(session.isTerminated, true);
    });

    test('Check session destroy in await state [Pull]', () async {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);

      //Pull
      Future.delayed(Duration(milliseconds: 100), () {
        session.forceTermination();
      });
      await session.pull();

      expect(session.isTerminated, true);
    });

    test('Check session destroy in await state [Pull]', () async {
      final sink = _DummySink();
      var session = SessionBuilder.create(1, sink, 82);

      //Push Pull
      Future.delayed(Duration(milliseconds: 100), () {
        session.forceTermination();
      });
      await session.pushPull([Uint8List(2)]);

      expect(session.isTerminated, true);
    });
  });
}
