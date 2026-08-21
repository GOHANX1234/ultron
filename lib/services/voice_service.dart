import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

class _QueuedAudioSentence {
  final String text;
  final Future<Uint8List?> audioFuture;

  _QueuedAudioSentence({
    required this.text,
    required this.audioFuture,
  });
}

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

  // Streaming Sentence Queue state
  int _currentSessionId = 0;
  bool _isStreamingActive = false;
  String _streamBuffer = '';
  final List<_QueuedAudioSentence> _sentenceQueue = [];
  bool _isPlayingQueue = false;

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

  /// Start a streaming TTS session before tokens begin arriving from the LLM.
  void startStreamingSession() {
    if (!_ttsEnabled || _ttsApiKey.isEmpty) return;
    _currentSessionId++;
    _isStreamingActive = true;
    _streamBuffer = '';
    _sentenceQueue.clear();
    _isPlayingQueue = false;
  }

  /// Feed an incoming text chunk (delta) from the LLM stream.
  /// Automatically splits on sentence boundaries and dispatches TTS pre-fetches.
  void feedStreamChunk(String chunk) {
    if (!_isStreamingActive || !_ttsEnabled || _ttsApiKey.isEmpty) return;
    _streamBuffer += chunk;
    _extractAndEnqueueSentences(_currentSessionId);
  }

  /// Signal that the LLM has finished streaming its response.
  /// Flushes any remaining sentence fragment in the buffer.
  void finishStreamingSession() {
    if (!_isStreamingActive) return;
    _isStreamingActive = false;
    final remaining = _streamBuffer.trim();
    _streamBuffer = '';
    if (remaining.isNotEmpty) {
      _enqueueSentence(remaining, _currentSessionId);
    }
    _ensurePlaybackLoopRunning(_currentSessionId);
  }

  /// Cancel any active streaming session and discard queued audio.
  void cancelStreamingSession() {
    stopSpeaking();
  }

  /// Split sentences from the stream buffer
  void _extractAndEnqueueSentences(int sessionId) {
    if (sessionId != _currentSessionId) return;

    // Matches sentence endings: . ! ? 。 ！ ？ or newlines followed by space/newline/EOF
    final regex = RegExp(r'([.!?。！？\n]+(\s+|$))');

    while (true) {
      final match = regex.firstMatch(_streamBuffer);
      if (match == null) break;

      final sentenceEndIndex = match.end;
      final sentenceCandidate =
          _streamBuffer.substring(0, sentenceEndIndex).trim();

      // Avoid splitting on tiny fragments like abbreviations (e.g., "Dr." or "1.")
      if (sentenceCandidate.length < 5 &&
          !sentenceCandidate.contains('\n') &&
          _isStreamingActive) {
        break;
      }

      _streamBuffer = _streamBuffer.substring(sentenceEndIndex);

      if (sentenceCandidate.isNotEmpty) {
        _enqueueSentence(sentenceCandidate, sessionId);
      }
    }
  }

  /// Clean text and immediately dispatch background TTS fetch
  void _enqueueSentence(String rawText, int sessionId) {
    if (sessionId != _currentSessionId) return;
    if (!_ttsEnabled || _ttsApiKey.isEmpty) return;

    final cleanText = _cleanTextForSpeech(rawText);
    if (cleanText.isEmpty) return;

    developer.log(
      'Queuing sentence for TTS [$sessionId]: "$cleanText"',
      name: 'VoiceService',
    );

    final audioFuture = _fetchAudioBytes(cleanText, sessionId);
    _sentenceQueue.add(_QueuedAudioSentence(
      text: cleanText,
      audioFuture: audioFuture,
    ));

    _ensurePlaybackLoopRunning(sessionId);
  }

  /// Background playback loop that seamlessly chains synthesized audio chunks
  Future<void> _ensurePlaybackLoopRunning(int sessionId) async {
    if (_isPlayingQueue || sessionId != _currentSessionId) return;
    _isPlayingQueue = true;

    while (sessionId == _currentSessionId) {
      if (_sentenceQueue.isEmpty) {
        if (!_isStreamingActive) {
          // Finished playing all queued sentences
          break;
        }
        // Wait briefly for next sentence to be streamed from LLM
        await Future.delayed(const Duration(milliseconds: 35));
        continue;
      }

      final item = _sentenceQueue.removeAt(0);
      Uint8List? audioBytes;
      try {
        audioBytes = await item.audioFuture;
      } catch (e) {
        audioBytes = null;
      }

      if (sessionId != _currentSessionId) break;
      if (audioBytes == null || audioBytes.isEmpty) continue;

      // Play this sentence and await its completion
      final completer = Completer<void>();
      StreamSubscription? completeSub;
      StreamSubscription? stateSub;

      void onDone() {
        completeSub?.cancel();
        stateSub?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      completeSub = _audioPlayer.onPlayerComplete.listen((_) => onDone());
      stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped || state == PlayerState.completed) {
          onDone();
        }
      });

      try {
        await _audioPlayer.play(BytesSource(audioBytes));
        // Safety timeout per sentence (35s)
        await completer.future.timeout(
          const Duration(seconds: 35),
          onTimeout: () => onDone(),
        );
      } catch (e) {
        onDone();
      }
    }

    if (sessionId == _currentSessionId) {
      _isPlayingQueue = false;
      _isSpeaking = false;
    }
  }

  /// Synthesize a text chunk to MP3 bytes via StepAudio API
  Future<Uint8List?> _fetchAudioBytes(String text, int sessionId) async {
    if (sessionId != _currentSessionId) return null;
    try {
      final requestBody = jsonEncode({
        'model': _ttsModel.isNotEmpty ? _ttsModel : defaultModel,
        'input': text,
        'voice': _ttsVoice.isNotEmpty ? _ttsVoice : defaultVoice,
        'response_format': defaultFormat,
      });

      final url = Uri.parse(
        _ttsEndpoint.isNotEmpty ? _ttsEndpoint : defaultEndpoint,
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
          .timeout(const Duration(seconds: 30));

      if (sessionId != _currentSessionId) return null;

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      } else {
        developer.log(
          'TTS API returned error [${response.statusCode}]: ${response.body}',
          name: 'VoiceService',
        );
        return null;
      }
    } catch (e) {
      if (sessionId == _currentSessionId) {
        developer.log('TTS fetch error: $e', name: 'VoiceService');
      }
      return null;
    }
  }

  /// Strip markdown, URLs, thinking tags and noise for natural speech
  String _cleanTextForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'`[^`]*`'), '')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'[*_~#>]+'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
        .trim();
  }

  /// Speak full text aloud using the sentence streaming queue
  Future<void> speak(String text) async {
    if (!_ttsEnabled || text.trim().isEmpty || _ttsApiKey.isEmpty) return;

    await stopSpeaking();
    startStreamingSession();
    feedStreamChunk(text);
    finishStreamingSession();
  }

  /// Stop speaking immediately and clear all queues
  Future<void> stopSpeaking() async {
    _currentSessionId++;
    _isStreamingActive = false;
    _streamBuffer = '';
    _sentenceQueue.clear();
    _isPlayingQueue = false;
    _isSpeaking = false;
    try {
      await _audioPlayer.stop();
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
    stopSpeaking();
    _speech.stop();
    _audioPlayer.dispose();
  }
}



