import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

class VoiceService {
  static const String defaultEndpoint =
      'https://api.hcnsec.cn/v1/audio/speech';
  static const String defaultModel = 'stepaudio-2.5-tts';
  static const String defaultVoice = 'cixingnansheng';
  static const String defaultFormat = 'mp3';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String _ttsApiKey = '';
  String _ttsEndpoint = defaultEndpoint;
  String _ttsModel = defaultModel;
  String _ttsVoice = defaultVoice;
  bool _ttsEnabled = true;

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isTtsEnabled => _ttsEnabled;
  String get ttsApiKey => _ttsApiKey;
  String get ttsEndpoint => _ttsEndpoint;
  String get ttsModel => _ttsModel;
  String get ttsVoice => _ttsVoice;
  bool get isConfigured => _ttsApiKey.isNotEmpty;

  VoiceService() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isSpeaking = state == PlayerState.playing;
    });
  }

  Future<void> init() async {
    if (_isInitialized) return;

    // Load TTS settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    _ttsApiKey = prefs.getString('tts_api_key') ?? '';
    _ttsEndpoint = prefs.getString('tts_endpoint') ?? defaultEndpoint;
    _ttsModel = prefs.getString('tts_model') ?? defaultModel;
    _ttsVoice = prefs.getString('tts_voice') ?? defaultVoice;
    _ttsEnabled = prefs.getBool('tts_enabled') ?? true;

    // Initialize STT
    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );
  }

  Future<void> saveSettings({
    required String apiKey,
    String? endpoint,
    String? model,
    String? voice,
    bool? enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    String cleanKey = apiKey.trim();
    if (cleanKey.toLowerCase().startsWith('bearer ')) {
      cleanKey = cleanKey.substring(7).trim();
    }

    _ttsApiKey = cleanKey;
    await prefs.setString('tts_api_key', cleanKey);

    if (endpoint != null && endpoint.trim().isNotEmpty) {
      _ttsEndpoint = endpoint.trim();
      await prefs.setString('tts_endpoint', _ttsEndpoint);
    }
    if (model != null && model.trim().isNotEmpty) {
      _ttsModel = model.trim();
      await prefs.setString('tts_model', _ttsModel);
    }
    if (voice != null && voice.trim().isNotEmpty) {
      _ttsVoice = voice.trim();
      await prefs.setString('tts_voice', _ttsVoice);
    }
    if (enabled != null) {
      _ttsEnabled = enabled;
      await prefs.setBool('tts_enabled', enabled);
    }
  }

  /// Speak text aloud using the StepAudio TTS cloud API
  Future<void> speak(String text) async {
    if (!_ttsEnabled || text.trim().isEmpty) return;

    if (_ttsApiKey.isEmpty) {
      developer.log(
        'TTS skipped: No TTS API Key configured.',
        name: 'VoiceService',
      );
      return;
    }

    // Clean text: strip markdown code fences, think tags, and URLs
    String cleanText = text
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'`[^`]*`'), '')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .trim();

    if (cleanText.isEmpty) return;

    // Truncate if exceptionally long to avoid timeout
    if (cleanText.length > 4000) {
      cleanText = cleanText.substring(0, 4000);
    }

    try {
      await stopSpeaking();

      final requestBody = jsonEncode({
        'model': _ttsModel.isNotEmpty ? _ttsModel : defaultModel,
        'input': cleanText,
        'voice': _ttsVoice.isNotEmpty ? _ttsVoice : defaultVoice,
        'response_format': defaultFormat,
      });

      final url = Uri.parse(_ttsEndpoint.isNotEmpty ? _ttsEndpoint : defaultEndpoint);

      developer.log(
        'Requesting TTS audio from $url with model: $_ttsModel, voice: $_ttsVoice',
        name: 'VoiceService',
      );

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_ttsApiKey',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        developer.log(
          'TTS audio received (${response.bodyBytes.length} bytes), playing...',
          name: 'VoiceService',
        );
        await _audioPlayer.play(BytesSource(response.bodyBytes));
      } else {
        developer.log(
          'TTS API returned error [${response.statusCode}]: ${response.body}',
          name: 'VoiceService',
        );
      }
    } catch (e) {
      developer.log('TTS speak error: $e', name: 'VoiceService');
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    try {
      await _audioPlayer.stop();
      _isSpeaking = false;
    } catch (e) {
      developer.log('TTS stop error: $e', name: 'VoiceService');
    }
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

  void dispose() {
    _speech.stop();
    _audioPlayer.dispose();
  }
}



