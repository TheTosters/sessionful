import 'dart:typed_data';

import 'package:sessionful/sessionful.dart';
import 'package:test/test.dart';

void main() {
  group('Buffer Combiner Tests', () {
    test('Add exact amount of data - no initial slice', () {
      final combiner = BuffersCombiner(18);
      Uint8List sub = Uint8List(9);
      for (int t = 0; t < sub.length; t++) {
        sub[t] = t;
      }
      combiner.add(sub);
      expect(combiner.isCompleted, false);
      combiner.add(sub);
      expect(combiner.isCompleted, true);
      final result = combiner.getCombined();
      for (int t = 0; t < 18; t++) {
        expect(result[t], t % 9);
      }
    });
    test('Add exact amount of data - with initial slice', () {
      Uint8List sub = Uint8List(9);
      Uint8List sub2 = Uint8List(9);
      for (int t = 0; t < sub.length; t++) {
        sub[t] = t;
        sub2[t] = 9 + t;
      }
      final combiner = BuffersCombiner(sub.length + sub2.length, sub);
      combiner.add(sub2);
      expect(combiner.isCompleted, true);
      final result = combiner.getCombined();
      for (int t = 0; t < 18; t++) {
        expect(result[t], t);
      }
    });

    test('Add too much data - accept none', () {
      Uint8List sub = Uint8List(9);
      Uint8List sub2 = Uint8List(9);
      for (int t = 0; t < sub.length; t++) {
        sub[t] = t;
        sub2[t] = 9 + t;
      }
      final combiner = BuffersCombiner(sub.length, sub);
      int tmp = combiner.add(sub2);
      expect(tmp, 0);
      expect(combiner.isCompleted, true);
      final result = combiner.getCombined();
      for (int t = 0; t < sub.length; t++) {
        expect(result[t], sub[t]);
      }
    });

    test('Add too much data - accept partial', () {
      Uint8List sub = Uint8List(18);
      for (int t = 0; t < sub.length; t++) {
        sub[t] = t;
      }
      final combiner = BuffersCombiner(sub.length ~/ 2);
      int tmp = combiner.add(sub);
      expect(tmp, sub.length ~/ 2);
      expect(combiner.isCompleted, true);
      final result = combiner.getCombined();
      for (int t = 0; t < result.length; t++) {
        expect(result[t], sub[t]);
      }
    });

    test('Create from too big data pack', () {
      Uint8List sub = Uint8List(18);
      try {
        BuffersCombiner(sub.length ~/ 2, sub);
        fail("Shouldn't be here");
      } catch (e) {
        expect(e, isArgumentError);
      }
    });
  });

  group('Unbounded Buffer Combiner Tests', () {
    test('Check work', () {
      Uint8List sub = Uint8List(9);
      for (int t = 0; t < sub.length; t++) {
        sub[t] = t;
      }
      final combiner = UnboundBuffersCombiner(sub);
      expect(combiner.size, sub.length);
      combiner.add(sub);
      expect(combiner.size, sub.length * 2);
      final result = combiner.getCombined();
      for (int t = 0; t < result.length; t++) {
        expect(result[t], sub[t % sub.length]);
      }
    });
  });
}
