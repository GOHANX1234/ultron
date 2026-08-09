import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  sherpa.OfflineTts? _sherpaTts;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isModelReady = false;
  bool _isDownloadingModel = false;

  bool get isListening => _isListening;
  bool get isModelReady => _isModelReady;
  bool get isDownloadingModel => _isDownloadingModel;

  /// Check if the TTS neural model files exist locally
  Future<bool> checkIsModelDownloaded() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/sherpa_onnx_piper');
      final modelFile = File('${modelDir.path}/en_US-lessac-medium.onnx');
      final tokensFile = File('${modelDir.path}/tokens.txt');
      return await modelFile.exists() && await tokensFile.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize STT
    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );

    // Initialize Sherpa-ONNX bindings & Piper VITS Male TTS model (only if already downloaded)
    await _initSherpaOnnx();
  }

  Future<void> _initSherpaOnnx() async {
    try {
      sherpa.initBindings();

      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/sherpa_onnx_piper');

      final modelPath = '${modelDir.path}/en_US-lessac-medium.onnx';
      final tokensPath = '${modelDir.path}/tokens.txt';
      final dataDirPath = '${modelDir.path}/espeak-ng-data';

      final modelFile = File(modelPath);
      final tokensFile = File(tokensPath);

      if (!await modelFile.exists() || !await tokensFile.exists()) {
        _isModelReady = false;
        return;
      }

      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: modelPath,
            tokens: tokensPath,
            dataDir: dataDirPath,
          ),
          numThreads: 2,
          debug: false,
        ),
      );

      _sherpaTts = sherpa.OfflineTts(config);
      _isModelReady = true;
    } catch (e) {
      debugPrint('Sherpa-ONNX initialization exception: $e');
    }
  }

  /// Explicitly download model files with progress callback
  Future<bool> downloadModelFiles({Function(double progress, String status)? onProgress}) async {
    if (_isDownloadingModel) return false;
    _isDownloadingModel = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/sherpa_onnx_piper');
      final modelPath = '${modelDir.path}/en_US-lessac-medium.onnx';
      final tokensPath = '${modelDir.path}/tokens.txt';

      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      const baseUrl =
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium';

      onProgress?.call(0.05, 'Downloading model tokens...');
      final tokensRes = await http.get(Uri.parse('$baseUrl/tokens.txt'));
      if (tokensRes.statusCode == 200) {
        await File(tokensPath).writeAsBytes(tokensRes.bodyBytes);
      } else {
        throw Exception('Failed downloading tokens file (${tokensRes.statusCode})');
      }

      onProgress?.call(0.10, 'Downloading neural TTS voice model (~63 MB)...');
      final request = http.Request('GET', Uri.parse('$baseUrl/en_US-lessac-medium.onnx'));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed downloading ONNX model file (${response.statusCode})');
      }

      final totalBytes = response.contentLength ?? 66300000;
      int downloadedBytes = 0;
      final file = File(modelPath);
      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        double progress = 0.10 + (downloadedBytes / totalBytes) * 0.85;
        if (progress > 0.95) progress = 0.95;
        onProgress?.call(
          progress,
          'Downloading voice model: ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
        );
      }

      await sink.flush();
      await sink.close();

      onProgress?.call(0.98, 'Initializing offline voice engine...');
      _isDownloadingModel = false;
      await _initSherpaOnnx();

      if (_isModelReady) {
        onProgress?.call(1.0, 'Voice model downloaded and ready!');
        return true;
      }
      return false;
    } catch (e) {
      _isDownloadingModel = false;
      debugPrint('Failed downloading Piper VITS model files: $e');
      rethrow;
    }
  }

  /// Convert Float32 audio samples into a standard 16-bit WAV file buffer
  Uint8List _createWavBuffer(Float32List samples, int sampleRate) {
    final int numSamples = samples.length;
    final int byteRate = sampleRate * 2; // 1 channel * 16-bit (2 bytes)
    final int dataSize = numSamples * 2;
    final int fileSize = 36 + dataSize;

    final ByteData buffer = ByteData(44 + dataSize);

    // RIFF Header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt subchunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size
    buffer.setUint16(20, 1, Endian.little);  // AudioFormat (PCM)
    buffer.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, 2, Endian.little);  // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    // 16-bit PCM Conversion
    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      double sample = samples[i].clamp(-1.0, 1.0);
      int sampleInt16 = (sample < 0) ? (sample * 32768).toInt() : (sample * 32767).toInt();
      buffer.setInt16(offset, sampleInt16, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  /// Speak text aloud using Sherpa-ONNX Piper VITS male voice
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      if (!_isModelReady || _sherpaTts == null) {
        await _initSherpaOnnx();
      }

      if (_sherpaTts != null) {
        // Generate high quality neural male speech
        final audio = _sherpaTts!.generate(text: text.trim());
        if (audio.samples.isNotEmpty) {
          final wavBytes = _createWavBuffer(audio.samples, audio.sampleRate);
          await _audioPlayer.stop();
          await _audioPlayer.play(BytesSource(wavBytes));
        }
      }
    } catch (e) {
      debugPrint('Sherpa-ONNX speak error: $e');
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _audioPlayer.stop();
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

