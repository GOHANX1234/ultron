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
import 'screen_automation_service.dart';

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

  /// The TTS gateway enforces a global concurrency limit (observed: 10) and
  /// *blocks* rather than failing fast when it is reached, so firing one
  /// request per sentence trips the limit on a single multi-sentence reply.
  /// Cap in-flight synthesis requests well below the server limit.
  static const int _maxConcurrentFetches = 2;

  /// Observed time-to-first-byte ranges from ~9s to ~92s when the gateway is
  /// queueing, so the per-request budget has to be generous or every fetch
  /// aborts and playback goes silent.
  static const Duration _fetchTimeout = Duration(seconds: 90);

  /// How many times to retry a request the gateway rejected as rate limited.
  static const int _maxRateLimitRetries = 2;

  int _activeFetches = 0;
  final List<Completer<void>> _fetchSlotWaiters = [];

  String? _lastTtsError;

  /// Human-readable reason the most recent synthesis attempt produced no audio,
  /// or null if TTS is healthy. Lets the UI distinguish a broken TTS from a
  /// deliberately silent one.
  String? get lastTtsError => _lastTtsError;

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
    _lastTtsError = null;
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
        _reportTtsFailure('synthesis threw for "${item.text}": $e');
      }

      if (sessionId != _currentSessionId) break;
      if (audioBytes == null || audioBytes.isEmpty) {
        // _fetchAudioBytes already reported the reason; note the dropped
        // sentence so a fully silent reply is traceable.
        developer.log(
          'Skipping sentence with no audio: "${item.text}"',
          name: 'VoiceService',
        );
        continue;
      }

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

    // Only clear the shared flags if this loop still owns the current session;
    // a superseded loop must not stomp on the successor's state.
    if (sessionId == _currentSessionId) {
      _isPlayingQueue = false;
      _isSpeaking = false;
    }
  }

  /// Wait until an in-flight synthesis slot frees up, then claim it.
  Future<void> _acquireFetchSlot() async {
    if (_activeFetches < _maxConcurrentFetches) {
      _activeFetches++;
      return;
    }
    // A released slot is handed straight to this waiter, so the count stays
    // owned by whoever holds it — the waiter must not increment again.
    final waiter = Completer<void>();
    _fetchSlotWaiters.add(waiter);
    await waiter.future;
  }

  /// Release a synthesis slot, transferring it directly to the next waiter so
  /// the in-flight count can never transiently exceed the cap.
  void _releaseFetchSlot() {
    while (_fetchSlotWaiters.isNotEmpty) {
      final waiter = _fetchSlotWaiters.removeAt(0);
      if (!waiter.isCompleted) {
        waiter.complete();
        return; // slot transferred, count unchanged
      }
    }
    _activeFetches--;
    if (_activeFetches < 0) _activeFetches = 0;
  }

  /// Record a TTS failure so it is visible in logcat and to the UI, instead of
  /// being swallowed into silence by the playback loop.
  void _reportTtsFailure(String reason) {
    _lastTtsError = reason;
    developer.log('TTS failure: $reason', name: 'VoiceService');
    // Fire-and-forget: the automation runs while the app is backgrounded, so
    // logcat is the only practical place to see this.
    ScreenAutomationService.logToNative('TTS failure: $reason');
  }

  /// Synthesize a text chunk to MP3 bytes via StepAudio API
  Future<Uint8List?> _fetchAudioBytes(String text, int sessionId) async {
    if (sessionId != _currentSessionId) return null;

    await _acquireFetchSlot();
    try {
      // Session may have been superseded while we waited for a slot.
      if (sessionId != _currentSessionId) return null;
      return await _fetchAudioBytesWithRetry(text, sessionId);
    } finally {
      _releaseFetchSlot();
    }
  }

  Future<Uint8List?> _fetchAudioBytesWithRetry(
    String text,
    int sessionId,
  ) async {
    for (var attempt = 0; attempt <= _maxRateLimitRetries; attempt++) {
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
            .timeout(_fetchTimeout);

        if (sessionId != _currentSessionId) return null;

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          _lastTtsError = null;
          return response.bodyBytes;
        }

        // 429 means the gateway's concurrency limit is saturated. Back off and
        // retry rather than dropping the sentence.
        if (response.statusCode == 429 && attempt < _maxRateLimitRetries) {
          final backoff = Duration(seconds: 2 * (attempt + 1));
          developer.log(
            'TTS rate limited (attempt ${attempt + 1}), retrying in '
            '${backoff.inSeconds}s: ${response.body}',
            name: 'VoiceService',
          );
          await Future.delayed(backoff);
          continue;
        }

        _reportTtsFailure(
          'HTTP ${response.statusCode} from TTS endpoint: ${response.body}',
        );
        return null;
      } on TimeoutException {
        if (sessionId != _currentSessionId) return null;
        // Retry a timeout at most once: three 90s attempts would block the head
        // of the playback queue for over four minutes.
        if (attempt == 0) {
          developer.log(
            'TTS timed out after ${_fetchTimeout.inSeconds}s, retrying once',
            name: 'VoiceService',
          );
          continue;
        }
        _reportTtsFailure(
          'timed out after ${_fetchTimeout.inSeconds}s (2 attempts)',
        );
        return null;
      } catch (e) {
        if (sessionId != _currentSessionId) return null;
        _reportTtsFailure('$e');
        return null;
      }
    }
    return null;
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



