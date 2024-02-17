import 'dart:typed_data';

import 'buffers_combiner.dart';
import 'session.dart';

typedef SessionObserver = void Function(Session);

///This class acts as a de-multiplexer of incoming data stream. It allows to identify and forward
///data to proper session. If no session match incoming data, new will be formed and passed to
///observer.
class SessionsDispatcher implements Sink<Uint8List> {
  final int sessionMarker;
  final List<Session> _sessions = [];
  final SessionObserver onNewSessionDiscovered;
  final SessionObserver onSessionTerminated;
  final Sink<Uint8List> outputSink;
  int _sessionsCounter = 0;
  bool _closed = false;
  UnboundBuffersCombiner? _combiner;

  SessionsDispatcher({
    required this.outputSink,
    required this.onNewSessionDiscovered,
    required this.onSessionTerminated,
    this.sessionMarker = 0x8F,
  });

  int _generateId() {
    int id;
    do {
      _sessionsCounter = (_sessionsCounter + 1) & 0x7FFFFFFF;
      id = ++_sessionsCounter;
    } while (_sessions.any((e) => e.sessionId == id));
    return id;
  }

  Session createSession() {
    final session = SessionBuilder.create(_generateId(), outputSink, sessionMarker);
    _sessions.add(session);
    return session;
  }

  void removeSession(Session s) {
    _sessions.removeWhere((e) => e.sessionId == s.sessionId);
  }

  @override
  void add(Uint8List data) {
    if (_closed) {
      throw Exception("[SessionsDispatcher] This sink is closed!");
    }
    final cb = _combiner;
    if (cb != null) {
      cb.add(data);
      if (cb.size > Session.headerSize) {
        data = cb.getCombined();
        _combiner = null;
        _innerAdd(data);
      }
    } else {
      _innerAdd(data);
    }
  }

  void _innerAdd(Uint8List data) {
    int? consumed;
    for (int t = 0; t < _sessions.length; t++) {
      final s = _sessions[t];
      consumed = s.consumePayload(data);
      if (consumed != null) {
        if (consumed == data.length) {
          if (s.isTerminated) {
            _sessions.removeAt(t);
            onSessionTerminated(s);
          } else {
            //Whole data was consumed, it might be situation that this session want more
            //unconditionally, move it to front of array to have this covered for next iteration
            if (t != 0) {
              //We move only if we are not already first
              final tmp = _sessions[0];
              _sessions[0] = s;
              _sessions[t] = tmp;
            }
          }
          break;
        } else {
          //Some data left, truncate buffer and feed again.
          if (s.isTerminated) {
            _sessions.removeAt(t);
            onSessionTerminated(s);
          }
          data = data.sublist(consumed);
          _innerAdd(data); //do recursive add
          break;
        }
      }
    }

    if (consumed == null) {
      final newSession = SessionBuilder.createFrom(data, sessionMarker, outputSink);
      if (newSession != null) {
        _sessions.insert(0, newSession);
        onNewSessionDiscovered(newSession);
        _innerAdd(data); //Since we added new destination feed again to itself for consumption
      } else {
        _combiner = UnboundBuffersCombiner(data);
      }
    }
  }

  @override
  void close() {
    _closed = true;
  }
}
