import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/timing/beat_grid.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  group('BeatGrid', () {
    test('step interval follows bpm and subdivision', () {
      expect(
        BeatGrid(anchor: Duration.zero, bpm: 120).stepInterval,
        const Duration(milliseconds: 500),
      );
      expect(
        BeatGrid(anchor: Duration.zero, bpm: 120, stepsPerBeat: 4).stepInterval,
        const Duration(milliseconds: 125),
      );
    });

    test('stepTime is anchor + n * interval', () {
      final grid = BeatGrid(anchor: _ms * 1000, bpm: 60);
      expect(grid.stepTime(0), _ms * 1000);
      expect(grid.stepTime(1), _ms * 2000);
      expect(grid.stepTime(10), _ms * 11000);
    });

    test('anchorStep shifts the index origin', () {
      final grid = BeatGrid(anchor: _ms * 1000, anchorStep: 8, bpm: 60);
      expect(grid.stepTime(8), _ms * 1000);
      expect(grid.stepTime(9), _ms * 2000);
      expect(grid.stepTime(7), Duration.zero);
    });

    test('no accumulated rounding error over long runs', () {
      // 113 BPM: 530973.45... us per beat, not representable in Duration.
      final grid = BeatGrid(anchor: Duration.zero, bpm: 113);
      const beats = 113 * 60; // one hour
      expect(grid.stepTime(beats), const Duration(hours: 1));
    });

    test('firstStepAtOrAfter finds the next grid step', () {
      final grid = BeatGrid(anchor: _ms * 1000, anchorStep: 4, bpm: 120);
      expect(grid.firstStepAtOrAfter(_ms * 1000), 4);
      expect(grid.firstStepAtOrAfter(_ms * 1001), 5);
      expect(grid.firstStepAtOrAfter(_ms * 1500), 5);
      expect(grid.firstStepAtOrAfter(_ms * 2499), 7);
      // Never earlier than the anchor step.
      expect(grid.firstStepAtOrAfter(Duration.zero), 4);
    });

    test('lastStepAtOrBefore finds the previous grid step', () {
      final grid = BeatGrid(anchor: _ms * 1000, anchorStep: 4, bpm: 120);
      expect(grid.lastStepAtOrBefore(_ms * 1000), 4);
      expect(grid.lastStepAtOrBefore(_ms * 1499), 4);
      expect(grid.lastStepAtOrBefore(_ms * 1500), 5);
      expect(grid.lastStepAtOrBefore(_ms * 999), 3);
    });

    test('retempo keeps the pivot step time and the step numbering', () {
      final grid = BeatGrid(anchor: Duration.zero, bpm: 120);
      // Beat 2 (index 2) is at 1000 ms; switch to 60 BPM from there.
      final slower = grid.retempo(pivotStep: 2, bpm: 60);
      expect(slower.stepTime(2), _ms * 1000);
      expect(slower.stepTime(3), _ms * 2000);
      expect(slower.stepTime(4), _ms * 3000);
      expect(slower.anchorStep, 2);
    });

    test('retempo can change the subdivision', () {
      final grid = BeatGrid(anchor: Duration.zero, bpm: 60);
      final eighths = grid.retempo(pivotStep: 1, bpm: 60, stepsPerBeat: 2);
      expect(eighths.stepTime(1), _ms * 1000);
      expect(eighths.stepTime(2), _ms * 1500);
    });

    test('reanchor moves a step to a new time and keeps the tempo', () {
      final grid = BeatGrid(anchor: Duration.zero, bpm: 120);
      final moved = grid.reanchor(step: 3, at: _ms * 5000);
      expect(moved.stepTime(3), _ms * 5000);
      expect(moved.stepTime(4), _ms * 5500);
      expect(moved.bpm, 120);
    });

    test('rejects non-positive bpm or subdivision', () {
      expect(
        () => BeatGrid(anchor: Duration.zero, bpm: 0),
        throwsArgumentError,
      );
      expect(
        () => BeatGrid(anchor: Duration.zero, bpm: 120, stepsPerBeat: 0),
        throwsArgumentError,
      );
    });
  });
}
