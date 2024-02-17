import 'dart:convert';
import 'dart:typed_data';

import 'package:sessionful/sessionful.dart';

class Client {
  final String name;
  late final SessionsDispatcher dispatcher;
  final List<Session> sessions = [];

  Client(this.name, AttachableSink incomingData, AttachableSink outgoingData) {
    dispatcher = SessionsDispatcher(
        outputSink: outgoingData,
        onNewSessionDiscovered: (session) {
          print("[$name] new session with id ${session.sessionId}");
          sessions.add(session);
        },
        onSessionTerminated: (session) {
          print("[$name] Terminate session with id ${session.sessionId}");
          sessions.removeWhere((e) => e.sessionId == session.sessionId);
        });
    incomingData.destination = dispatcher;
  }

  Session? _getSessionById(int sessionId) {
    Session? session;
    for (var s in sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    return session;
  }

  ///Try to send in specified session, if session not exist create new one (id will be generated)
  int sendInSession(int sessionId, String data) {
    Session? session = _getSessionById(sessionId);
    if (session == null) {
      session = dispatcher.createSession();
      sessions.add(session);
    }
    final payload = utf8.encoder.convert(data);
    session.push([payload]);
    return session.sessionId;
  }

  String? readFromSession(int sessionId) {
    String? result;
    Session? session = _getSessionById(sessionId);
    final payload = session?.maybePull();
    if (payload != null) {
      result = utf8.decoder.convert(payload);
    }
    return result;
  }
}

class AttachableSink implements Sink<Uint8List> {
  Sink<Uint8List>? destination;

  @override
  void add(Uint8List data) => destination?.add(data);

  @override
  void close() => destination?.close();
}

class Transport {
  final AttachableSink fromClientAToB = AttachableSink();
  final AttachableSink fromClientBToA = AttachableSink();
}

void main() {
  final transport = Transport();
  final clientA = Client("A", transport.fromClientAToB, transport.fromClientBToA);
  final clientB = Client("B", transport.fromClientBToA, transport.fromClientAToB);

  final sessionId1 = clientA.sendInSession(-1, "This text is send in session 1");
  final sessionId2 = clientA.sendInSession(-1, "This text is send in session 2");

  for (Session s in clientB.sessions) {
    final incomingText = clientB.readFromSession(s.sessionId);
    print("ClientB [Session ${s.sessionId}] got text: $incomingText");
  }

  clientB.sendInSession(clientB.sessions.first.sessionId, "This is response");

  final incomingText = clientA.readFromSession(sessionId1);
  print("ClientA [Session $sessionId1] got response: $incomingText");
}
