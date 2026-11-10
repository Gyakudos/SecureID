import 'package:flutter_tts/flutter_tts.dart';

/// Reads vault summaries and details aloud for low-vision users.
abstract class SpeechService {
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}

/// A [SpeechService] backed by the platform text-to-speech engine.
///
/// The Windows and Android engines use the voice installed on the device, so
/// nothing is sent to a network service.
class FlutterTtsSpeechService implements SpeechService {
  FlutterTtsSpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Some engines report completion differently; speaking still works.
    }
    try {
      await _tts.setSpeechRate(0.48);
    } catch (_) {
      // Keep the platform default.
    }
    try {
      await _tts.setVolume(1.0);
    } catch (_) {
      // Keep the platform default.
    }
    try {
      await _tts.setPitch(1.0);
    } catch (_) {
      // Keep the platform default.
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _configure();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop, or the engine is unavailable.
    }
  }

  @override
  Future<void> dispose() => stop();
}
