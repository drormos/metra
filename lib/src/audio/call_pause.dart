import '../controller/metronome_controller.dart';

/// Phone and VoIP calls, like music apps: a ringing or active call stops
/// the click, and it starts again when the call ends. Starting the click
/// during the call cancels the resume.
class CallPause {
  /// [stop] is the media handler's stop, so the stopped card stays.
  CallPause(this._controller, {Future<void> Function()? stop})
    : _stop = stop ?? (() async => _controller.stop()) {
    _controller.addListener(() {
      if (_inCall && _controller.isPlaying) _resume = false;
    });
  }

  final MetronomeController _controller;
  final Future<void> Function() _stop;
  bool _inCall = false;
  bool _resume = false;

  Future<void> callChanged({required bool active}) async {
    if (active == _inCall) return;
    _inCall = active;
    if (active) {
      if (!_controller.isPlaying) return;
      await _stop();
      _resume = true;
    } else if (_resume) {
      _resume = false;
      await _controller.play();
    }
  }
}
