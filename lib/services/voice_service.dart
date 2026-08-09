import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _voiceSelected = false;

  bool get isListening => _isListening;

  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );

    // Default TTS configuration for natural deep male AI assistant (Ultron style)
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48); // Slightly slower for clarity & authority
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.88); // Natural deep male tone without robotic pitch distortion

    await _selectMaleVoice();
  }

  Future<void> _selectMaleVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List && voices.isNotEmpty) {
        Map? bestMaleVoice;
        int highestScore = -999;

        for (var voice in voices) {
          if (voice is Map) {
            final name = (voice['name'] ?? '').toString().toLowerCase();
            final locale = (voice['locale'] ?? '').toString().toLowerCase();
            final gender = (voice['gender'] ?? '').toString().toLowerCase();

            // English voices preferred
            if (locale.isNotEmpty && !locale.startsWith('en')) continue;

            int score = 0;

            // 1. Comprehensive Female Voice Exclusion
            final isFemale = gender == 'female' ||
                name.contains('female') ||
                name.contains('woman') ||
                name.contains('girl') ||
                name.contains('lady') ||
                name.contains('mother') ||
                name.contains('zira') ||
                name.contains('hazel') ||
                name.contains('samantha') ||
                name.contains('victoria') ||
                name.contains('karen') ||
                name.contains('fiona') ||
                name.contains('moira') ||
                name.contains('veena') ||
                name.contains('nora') ||
                name.contains('eva') ||
                name.contains('jenny') ||
                name.contains('aria') ||
                name.contains('anna') ||
                name.contains('serena') ||
                name.contains('catherine') ||
                name.contains('susan') ||
                name.contains('lisa') ||
                name.contains('melanie') ||
                // Google TTS Female voice patterns:
                name.contains('en-us-x-sfa') ||
                name.contains('en-us-x-sfb') ||
                name.contains('en-us-x-sfc') ||
                name.contains('en-us-x-sfe') ||
                name.contains('en-us-x-sfg') ||
                name.contains('en-us-x-sfh') ||
                name.contains('en-us-x-sfi') ||
                name.contains('en-us-x-tpa') ||
                name.contains('en-us-x-tpb') ||
                name.contains('en-us-x-tpc') ||
                name.contains('en-us-x-tpd') ||
                name.contains('en-us-x-tpe') ||
                name.contains('en-us-x-tpf') ||
                name.contains('en-us-x-ioa') ||
                name.contains('en-us-x-ioc') ||
                name.contains('en-us-x-iod') ||
                name.contains('en-us-x-lfe') ||
                name.contains('en-us-x-rgf') ||
                name.contains('en-us-x-pfi') ||
                name.contains('en-gb-x-gbc') ||
                name.contains('en-gb-x-gbd') ||
                name.contains('en-gb-x-sfc') ||
                // Samsung & SVOX Female voice patterns:
                name.contains('_f00') ||
                name.contains('_f0') ||
                name.contains('_f1') ||
                name.contains('_f2') ||
                name.contains('_female') ||
                // Espeak Female patterns:
                name.contains('+f1') ||
                name.contains('+f2') ||
                name.contains('+f3') ||
                name.contains('+f4');

            if (isFemale) {
              score -= 1000;
            }

            // 2. Male Voice High-Priority Matching
            if (gender == 'male') score += 100;

            // Google TTS Male voice identifiers:
            if (name.contains('en-us-x-iom') || // Deep US Male
                name.contains('en-us-x-iob') || // US Male
                name.contains('en-us-x-iol') || // US Male
                name.contains('en-us-x-sfd') || // US Male Standard
                name.contains('en-us-x-gqd') || // US Male
                name.contains('en-us-x-und') || // US Male
                name.contains('en-us-x-mwa') || // US Male
                name.contains('en-us-x-rod') || // US Male
                name.contains('en-us-x-std') || // US Male
                name.contains('en-us-x-dfz')) { // US Male
              score += 90;
            }

            if (name.contains('en-gb-x-rdb') || // UK Male
                name.contains('en-gb-x-fis') || // UK Male
                name.contains('en-gb-x-gba') || // UK Male
                name.contains('en-gb-x-gbb')) { // UK Male
              score += 85;
            }

            // Name-based male indicators:
            if (name.contains('male') ||
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
                name.contains('oliver') ||
                name.contains('arthur') ||
                name.contains('rishi') ||
                name.contains('ryan') ||
                name.contains('chris') ||
                name.contains('jarvis') ||
                name.contains('ultron') ||
                name.contains('_m0') ||
                name.contains('_m1') ||
                name.contains('_m2') ||
                name.contains('_m_') ||
                name.contains('-m-') ||
                name.contains('+m1') ||
                name.contains('+m2') ||
                name.contains('+m3')) {
              score += 50;
            }

            // Base preference for en-US locale
            if (locale == 'en-us' || locale == 'en_us') score += 10;

            if (score > highestScore) {
              highestScore = score;
              bestMaleVoice = voice;
            }
          }
        }

        if (bestMaleVoice != null && highestScore > -500) {
          final voiceMap = <String, String>{
            "name": bestMaleVoice["name"].toString(),
            "locale": bestMaleVoice["locale"].toString(),
          };
          await _tts.setVoice(voiceMap);
          _voiceSelected = true;
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
    if (!_isInitialized) {
      await init();
    } else if (!_voiceSelected) {
      await _selectMaleVoice();
    }
    await _tts.setPitch(0.88); // Natural deep male tone
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

