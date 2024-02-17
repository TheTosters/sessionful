import 'dart:async';
import 'dart:typed_data';

import 'package:sessionful/src/sessions_dispatcher.dart';

import 'buffers_combiner.dart';

///This object represent single channel of communication. It wraps data with envelope which
///allows [SessionsDispatcher] to dispatch bytes to proper Sessions. This object should be used
///to send and receive data from other party multiplexing multiple session on single data channel.
///
/// There are two major use cases for this class:
/// 1. Call which returns data is executed, no other communication is allowed across this session.
///    This can be achieved by call to [pushPull] method
/// 2. Single send data can result in multiple incoming data. Co cover this use combination of
///    [push], [maybePull] and [pull] methods.
///
/// Keep in mind mixing [pushPull] and [pull]/[maybePull] is not allowed and will lead to exception.
class Session {
  static const int _defaultSessionMarker = 0x8F;

  //[0x8F: 1b][sessionId(int): 4b][PayloadSize(int): 4b]
  static const int headerSize = 1 + 4 + 4;
  static const int _offsetSessionId = 1;
  static const int _offsetPayloadSize = 5;

  final int sessionMarker;
  final int sessionId;
  final Sink<Uint8List> sink;
  Completer<Uint8List>? _condition;
  final List<Uint8List> _incomingData = [];
  BuffersCombiner? _combiner;
  bool _isTerminated = false;

  bool get isEmpty => _incomingData.isEmpty;

  bool get isNotEmpty => _incomingData.isNotEmpty;

  bool get isTerminated => _isTerminated;

  Session._(this.sessionId, this.sink, {this.sessionMarker = _defaultSessionMarker});

  void clear() => _incomingData.clear();

  ///Sends payload into other party, and waits for response.
  Future<Uint8List> pushPull(List<Uint8List> data) async {
    if (_incomingData.isNotEmpty) {
      throw Exception("Session is not fully read, call to this method will give wrong results!");
    }
    if (_condition != null) {
      throw Exception("[Session $sessionId] Already in waiting for data state!");
    }
    final wait = Completer<Uint8List>();
    _condition = wait;

    final payloadSize = data.fold(0, (p, e) => p + e.length);
    _sendSessionHeader(payloadSize);
    for (final b in data) {
      sink.add(b);
    }
    final result = await wait.future;
    _condition = null;
    return result;
  }

  ///Sends data to other party, doesn't expect response.
  void push(List<Uint8List> data) {
    final payloadSize = data.fold(0, (p, e) => p + e.length);
    _sendSessionHeader(payloadSize);
    for (final b in data) {
      sink.add(b);
    }
  }

  ///Check is any data are in receive buffer, if yes take first portion of data, otherwise get null
  Uint8List? maybePull() {
    if (_condition != null) {
      throw Exception("[Session $sessionId] Already in waiting for data state!");
    }
    Uint8List? result;
    if (_incomingData.isNotEmpty) {
      result = _incomingData.first;
      _incomingData.removeAt(0);
    }
    return result;
  }

  ///Get data from buffer if nothing is in buffer wait for incoming data.
  Future<Uint8List> pull() async {
    if (_condition != null) {
      throw Exception("[Session $sessionId] Already in waiting for data state!");
    }
    Uint8List result;
    if (_incomingData.isNotEmpty) {
      result = _incomingData.first;
      _incomingData.removeAt(0);
    } else {
      //buffer was empty, just wait for next incoming data
      final wait = Completer<Uint8List>();
      _condition = wait;
      result = await wait.future;
    }
    return result;
  }

  void _sendSessionHeader(int payloadSize) {
    //[0x8F: 1b][sessionId(int): 4b][PayloadSize(int): 4b]
    final byteList = Uint8List(headerSize);
    final rawData = ByteData.view(byteList.buffer);
    rawData.setUint8(0, sessionMarker);
    rawData.setUint32(_offsetSessionId, sessionId);
    rawData.setUint32(_offsetPayloadSize, payloadSize);
    sink.add(byteList);
  }

  ///Conditionally consumes data package. Package will be consumed in two cases:
  ///
  ///1. Data informing about start session and sessionId match for this object
  ///2. Previous package was matched (point 1) but expected data size is larger then was delivered
  ///   in point 1. In that situation this session will consume as many bytes as it need to fill
  ///   buffer
  ///
  ///Returns Null if not interested in this data, if part of buffer is consumed then number of
  /// consumed bytes is returned.
  int? consumePayload(Uint8List package) {
    int? result;
    final cb = _combiner;
    if (cb != null) {
      result = cb.add(package);
      if (cb.isCompleted) {
        _handlePayload(cb.getCombined());
        _combiner = null;
      }
    } else {
      if (package.length >= headerSize) {
        final rawData = ByteData.view(package.buffer);
        if (rawData.getUint8(0) != sessionMarker) {
          throw Exception("Unexpected Byte [${rawData.getUint8(0)}] it should be [$sessionMarker]");
        }
        if (rawData.getUint32(_offsetSessionId) == sessionId) {
          result = _innerConsume(package);
        }
      }
    }
    return result;
  }

  int _innerConsume(Uint8List package) {
    int result;
    final rawData = ByteData.view(package.buffer);
    final expPayloadSize = rawData.getUint32(_offsetPayloadSize);
    if (expPayloadSize == 0xFFFFFFFF) {
      _isTerminated = true;
      return headerSize;
    }
    if (expPayloadSize <= package.length - headerSize) {
      //we got whole payload right now, happy :)
      final payload = package.sublist(headerSize, headerSize + expPayloadSize);
      _handlePayload(payload);
      result = headerSize + expPayloadSize;
    } else {
      //part of expected data, work with this...
      _combiner = BuffersCombiner(expPayloadSize, package.sublist(headerSize));
      result = package.length;
    }
    return result;
  }

  void _handlePayload(Uint8List payload) {
    if (_condition != null) {
      _condition!.complete(payload);
    } else {
      _incomingData.add(payload);
    }
  }

  ///Send special payload which inform receiver that this session is no longer valid and should
  ///be destroyed on receiver side.
  void sendTermination() {
    _sendSessionHeader(0xFFFFFFFF);
    _isTerminated = true;
  }
}

class SessionBuilder {
  static Session create(int generateId, Sink<Uint8List> outputSink, int sessionMarker) =>
      Session._(generateId, outputSink, sessionMarker: sessionMarker);

  static Session? createFrom(Uint8List payload, int sessionMarker, Sink<Uint8List> outputSink) {
    final rawData = ByteData.view(payload.buffer);
    Session? result;
    if (payload.length >= Session.headerSize && rawData.getUint8(0) == sessionMarker) {
      final sessionId = rawData.getUint32(Session._offsetSessionId);
      result = Session._(sessionId, outputSink, sessionMarker: sessionMarker);
    }

    return result;
  }
}
