import 'dart:math' as math;
import 'dart:typed_data';

/// The pitch of one frame of microphone samples, on the phone (ui-spec.md
/// "Tuner"): the McLeod Pitch Method. Its normalized square difference
/// function (NSDF) comes from an FFT autocorrelation; the first peak
/// within [_keyThreshold] of the highest is the period (no octave jumps),
/// refined by a parabola through its three samples. Good to well under a
/// cent on a steady tone from E2 to E6.
class PitchDetector {
  PitchDetector(this.sampleRate)
    : frameSize = _pow2AtLeast(sampleRate * 0.085),
      _minLag = (sampleRate / maxHz).floor(),
      _maxLag = (sampleRate / minHz).ceil() {
    _fftSize = frameSize * 2;
    _re = Float64List(_fftSize);
    _im = Float64List(_fftSize);
  }

  /// Below a low E on a bass's open string is out of range (E1 is 41 Hz;
  /// the spec asks from E2, the guitar's low string).
  static const minHz = 60.0;
  static const maxHz = 1500.0;

  /// Quieter than this (RMS of full scale, −54 dBFS) is silence. The
  /// unprocessed microphone is quiet: a speaker a metre away read 0.007.
  static const silence = 0.002;

  /// How periodic a frame must be (NSDF peak, 0–1) to count as a note.
  static const clarity = 0.85;
  static const _keyThreshold = 0.9;

  final int sampleRate;

  /// Samples per frame: ~85 ms, a power of two (4096 at 48 kHz), so even
  /// the low E has several periods in it.
  final int frameSize;
  final int _minLag;
  final int _maxLag;
  late final int _fftSize;
  late final Float64List _re;
  late final Float64List _im;

  /// The frequency in Hz, or null for silence or no clear pitch. [frame]
  /// holds [frameSize] samples in −1…1.
  double? detect(Float32List frame) {
    final n = frameSize;
    assert(frame.length == n);
    var mean = 0.0;
    for (final x in frame) {
      mean += x;
    }
    mean /= n;
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      final x = frame[i] - mean;
      _re[i] = x;
      energy += x * x;
    }
    if (math.sqrt(energy / n) < silence) return null;
    _re.fillRange(n, _fftSize, 0);
    _im.fillRange(0, _fftSize, 0);
    // Autocorrelation r(τ): the inverse FFT of the power spectrum.
    _fft(_re, _im, inverse: false);
    for (var i = 0; i < _fftSize; i++) {
      _re[i] = _re[i] * _re[i] + _im[i] * _im[i];
      _im[i] = 0;
    }
    _fft(_re, _im, inverse: true);
    // NSDF: 2 r(τ) / m(τ), m(τ) the energy of both overlapping parts.
    final maxLag = math.min(_maxLag, n - 1);
    final nsdf = Float64List(maxLag + 2);
    var m = 2 * _re[0] / _fftSize;
    for (var tau = 0; tau <= maxLag + 1 && tau < n; tau++) {
      if (tau > 0) {
        final a = frame[tau - 1] - mean;
        final b = frame[n - tau] - mean;
        m -= a * a + b * b;
      }
      nsdf[tau] = m > 0 ? 2 * (_re[tau] / _fftSize) / m : 0;
    }
    // Key maxima: the highest point of each positive lobe after the first
    // zero crossing, from the minimum lag on.
    final peaks = <int>[];
    var tau = 1;
    while (tau <= maxLag && nsdf[tau] > 0) {
      tau++;
    }
    while (tau <= maxLag) {
      while (tau <= maxLag && nsdf[tau] <= 0) {
        tau++;
      }
      var best = -1;
      while (tau <= maxLag && nsdf[tau] > 0) {
        if (tau >= _minLag && (best < 0 || nsdf[tau] > nsdf[best])) {
          best = tau;
        }
        tau++;
      }
      if (best > 0) peaks.add(best);
    }
    if (peaks.isEmpty) return null;
    final highest = peaks.map((p) => nsdf[p]).reduce(math.max);
    if (highest < clarity) return null;
    final peak = peaks.firstWhere((p) => nsdf[p] >= _keyThreshold * highest);
    final (a, b, c) = (nsdf[peak - 1], nsdf[peak], nsdf[peak + 1]);
    final denominator = a - 2 * b + c;
    final shift = denominator == 0 ? 0.0 : 0.5 * (a - c) / denominator;
    return sampleRate / (peak + shift);
  }

  static int _pow2AtLeast(double v) {
    var n = 1;
    while (n < v) {
      n <<= 1;
    }
    return n;
  }

  /// In-place radix-2 FFT; the inverse is unscaled.
  static void _fft(Float64List re, Float64List im, {required bool inverse}) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i], ti = im[i];
        re[i] = re[j];
        im[i] = im[j];
        re[j] = tr;
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = (inverse ? 2 : -2) * math.pi / len;
      final (wr, wi) = (math.cos(angle), math.sin(angle));
      for (var i = 0; i < n; i += len) {
        var (cr, ci) = (1.0, 0.0);
        for (var k = 0; k < len ~/ 2; k++) {
          final (ur, ui) = (re[i + k], im[i + k]);
          final xr = re[i + k + len ~/ 2], xi = im[i + k + len ~/ 2];
          final vr = xr * cr - xi * ci, vi = xr * ci + xi * cr;
          re[i + k] = ur + vr;
          im[i + k] = ui + vi;
          re[i + k + len ~/ 2] = ur - vr;
          im[i + k + len ~/ 2] = ui - vi;
          (cr, ci) = (cr * wr - ci * wi, cr * wi + ci * wr);
        }
      }
    }
  }
}
