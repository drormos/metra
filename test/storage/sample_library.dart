import 'package:flutter/material.dart' show ThemeMode;
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';

/// One library with every saved field set to a non-default value: the
/// schema guard serializes it and compares with the snapshot for the
/// current format (`test/fixtures/library_v<N>/`). A new saved field gets a
/// non-default value here (see the data-format-change skill).
final sampleLibrary = Library(
  songs: [
    Song(
      id: 'song-a',
      name: 'Dead Weight',
      bpm: 128,
      pattern: MetronomePattern.simple(
        beatsPerBar: 7,
        stepsPerBeat: 2,
        beatUnit: 8,
      ).cycleBeat(2).toggleCell(3, 1).withPolyrhythm(3).cyclePulse(1),
      onStart: const OnStart(
        countInOn: true,
        countInBars: 2,
        speedUp: true,
        changeBy: -3,
        every: 4,
        upTo: 90,
        stopOn: true,
        stopBy: StopBy.bars,
        stopBars: 64,
        stopTime: Duration(minutes: 7, seconds: 30),
      ),
      editedAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
      playedAt: DateTime.fromMillisecondsSinceEpoch(1760100000000),
    ),
    const Song(
      id: 'song-b',
      name: 'Slow Blues',
      bpm: 64,
      pattern: MetronomePattern.standard(),
    ),
  ],
  setlists: [
    Setlist(
      id: 'set-1',
      name: 'Friday set',
      songIds: const ['song-a', 'song-b', 'song-a'],
      playedAt: DateTime.fromMillisecondsSinceEpoch(1760200000000),
    ),
  ],
  lastBpm: 96,
  lastPattern: MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 3),
  lastOnStart: const OnStart(countInOn: true, stopOn: true),
  visualOffset: const Duration(milliseconds: 20),
  clickSound: ClickSound.bell,
  themeMode: ThemeMode.light,
  vibrate: false,
  keepScreenOn: KeepScreenOn.whilePlaying,
  volumes: const ClickVolumes(
    accent: 0.9,
    beat: 0.7,
    subdivision: 0.3,
    polyrhythm: 0.6,
  ),
  activeSetlistId: 'set-1',
  currentSongId: 'song-a',
  currentPosition: 2,
  tipsSeen: const {'edit-first-load', 'set-swipe-hint'},
  stageMode: true,
);
