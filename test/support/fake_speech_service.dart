import 'package:secure_id/services/speech_service.dart';

/// Records spoken text without touching a platform text-to-speech engine.
class FakeSpeechService implements SpeechService {
  final List<String> spoken = [];
  int stops = 0;
  bool disposed = false;
  bool fail = false;

  @override
  Future<void> speak(String text) async {
    if (fail) throw StateError('speech failed');
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
