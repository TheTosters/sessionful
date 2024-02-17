import 'dart:typed_data';

class BuffersCombiner {
  final List<Uint8List> _slices = [];
  final int expectedSize;
  int _currentSize;

  bool get isCompleted => _currentSize == expectedSize;

  BuffersCombiner(this.expectedSize, [Uint8List? firstSlice])
      : _currentSize = firstSlice?.length ?? 0 {
    if (_currentSize > expectedSize) {
      throw ArgumentError(
          "Can't create BuffersCombiner with initial slice bigger then expected buffer");
    }
    if (firstSlice != null) {
      _slices.add(firstSlice);
    }
  }

  int add(Uint8List slice) {
    final toConsume = expectedSize - _currentSize;
    final subSlice = slice.length <= toConsume ? slice : Uint8List.view(slice.buffer, 0, toConsume);
    _currentSize += subSlice.length;
    _slices.add(subSlice);
    return subSlice.length;
  }

  Uint8List getCombined() {
    final totalSize = _slices.fold(0, (p, e) => p + e.length);
    if (totalSize != expectedSize) {
      throw Exception("Buffer is not fully filled");
    }
    final result = Uint8List(totalSize);
    int offset = 0;
    for (final s in _slices) {
      result.setRange(offset, offset + s.length, s);
      offset += s.length;
    }
    return result;
  }
}

class UnboundBuffersCombiner {
  final List<Uint8List> _slices = [];

  int get size => _slices.fold(0, (p, e) => p + e.length);

  UnboundBuffersCombiner(firstSlice) {
    _slices.add(firstSlice);
  }

  void add(Uint8List slice) => _slices.add(slice);

  Uint8List getCombined() {
    final totalSize = _slices.fold(0, (p, e) => p + e.length);
    final result = Uint8List(totalSize);
    int offset = 0;
    for (final s in _slices) {
      result.setRange(offset, offset + s.length, s);
      offset += s.length;
    }
    return result;
  }
}
