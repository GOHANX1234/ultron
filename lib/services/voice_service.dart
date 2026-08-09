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
    await _tts.setPitch(0.50); // Deep male voice pitch

    await _selectMaleVoice();
  }

  Future<void> _selectMaleVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List && voices.isNotEmpty) {
        Map? selectedVoice;
        Map? fallbackVoice;

        for (var voice in voices) {
          if (voice is Map) {
            final name = (voice['name'] ?? '').toString().toLowerCase();
            final locale = (voice['locale'] ?? '').toString().toLowerCase();
            final gender = (voice['gender'] ?? '').toString().toLowerCase();

            if (locale.isNotEmpty && !locale.startsWith('en')) continue;

            // Explicit female voice filters to avoid (including Google TTS female identifiers)
            final isFemale = name.contains('female') ||
                name.contains('woman') ||
                name.contains('girl') ||
                name.contains('zira') ||
                name.contains('hazel') ||
                name.contains('samantha') ||
                name.contains('victoria') ||
                name.contains('karen') ||
                name.contains('fiona') ||
                name.contains('moira') ||
                name.contains('veena') ||
                name.contains('en-us-x-sfg') || // Google US Female
                name.contains('en-us-x-tpf') || // Google US Female
                name.contains('en-us-x-tpc') || // Google US Female
                name.contains('en-us-x-sfa') ||
                name.contains('en-us-x-sfb') ||
                name.contains('en-us-x-sfe') ||
                name.contains('en-us-x-sfh') ||
                gender == 'female';

            if (isFemale) continue;

            // Save first non-female voice as potential fallback
            fallbackVoice ??= voice;

            // Explicit male voice filters (Android Google TTS male tags & standard voices)
            final isMale = name.contains('male') ||
                name.contains('guy') ||
                name.contains('man') ||
                name.contains('david') ||
                name.contains('james') ||
                name.contains('daniel') ||
                name.contains('george') ||
                name.contains('alex') ||
                name.contains('fred') ||
                name.contains('bruce') ||
                name.contains('aaron') ||
                name.contains('en-us-x-iom') || // Google US Male
                name.contains('en-us-x-iob') || // Google US Male
                name.contains('en-us-x-iol') || // Google US Male
                name.contains('en-us-x-sfd') || // Google US Male
                name.contains('en-us-x-gqd') || // Google US Male
                name.contains('en-us-x-und') || // Google US Male
                gender == 'male';

            if (isMale) {
              selectedVoice = voice;
              break;
            }
          }
        }

        final targetVoice = selectedVoice ?? fallbackVoice;
        if (targetVoice != null) {
          await _tts.setVoice({
            "name": targetVoice["name"].toString(),
            "locale": targetVoice["locale"].toString(),
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
      await _tts.setPitch(0.50);
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
