import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );

    // Configure TTS with deep male voice
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.70); // Deep male voice pitch

    await _selectMaleVoice();
  }

  Future<void> _selectMaleVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List && voices.isNotEmpty) {
        Map? selectedVoice;
        for (var voice in voices) {
          if (voice is Map) {
            final name = (voice['name'] ?? '').toString().toLowerCase();
            final locale = (voice['locale'] ?? '').toString().toLowerCase();
            final gender = (voice['gender'] ?? '').toString().toLowerCase();

            if (locale.isNotEmpty && !locale.startsWith('en')) continue;

            // Skip explicit female voices
            if (name.contains('female') ||
                name.contains('woman') ||
                name.contains('girl') ||
                name.contains('zira') ||
                name.contains('hazel') ||
                name.contains('samantha') ||
                name.contains('victoria') ||
                gender == 'female') {
              continue;
            }

            // High priority male voices (Android Google TTS male models & standard voices)
            if (name.contains('male') ||
                name.contains('guy') ||
                name.contains('man') ||
                name.contains('david') ||
                name.contains('james') ||
                name.contains('daniel') ||
                name.contains('george') ||
                name.contains('alex') ||
                name.contains('fred') ||
                name.contains('en-us-x-sfg') ||
                name.contains('en-us-x-iom') ||
                name.contains('en-us-x-iob') ||
                name.contains('en-us-x-tpf') ||
                name.contains('en-us-x-tpc') ||
                name.contains('en-us-x-iol') ||
                name.contains('en-us-x-sfd') ||
                name.contains('en-us-x-gqd') ||
                gender == 'male') {
              selectedVoice = voice;
              break;
            }
          }
        }

        if (selectedVoice != null) {
          await _tts.setVoice({
            "name": selectedVoice["name"],
            "locale": selectedVoice["locale"]
          });
        }
      }
    } catch (_) {}
  }

  /// Start listening for speech. Returns transcribed text via callback.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;

    _isListening = true;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
          onDone();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
      ),
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  /// Speak text aloud
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _selectMaleVoice();
      await _tts.setPitch(0.70);
    } catch (_) {}
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
  }
}
