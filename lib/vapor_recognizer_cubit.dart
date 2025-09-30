import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:bassem_flutter/dart_ffi.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffi/ffi.dart';

// Your FFI header/types

/// ************
/// States (same as your previous VaporRecognizer* set)
abstract class VaporRecognizerStates {}
class VaporRecognizerInitialState extends VaporRecognizerStates {}
class VaporRecognizerOnStartRecognitionState extends VaporRecognizerStates {}
class VaporRecognizerOnStopRecognitionState extends VaporRecognizerStates {}
class VaporRecognizerOnErrorRecognitionState extends VaporRecognizerStates {
  final String message;
  VaporRecognizerOnErrorRecognitionState(this.message);
  @override
  List<Object?> get props => [message];
}
class VaporRecognizerOnErrorMicInUsedState extends VaporRecognizerStates {}
class VaporRecognizerOnErrorRecognizerStartState extends VaporRecognizerStates {}
class VaporRecognizerOnResultState extends VaporRecognizerStates {
  final String transcript;
  final bool isFinal;
  VaporRecognizerOnResultState(this.transcript, this.isFinal);
  @override
  List<Object?> get props => [transcript, isFinal];
}

/// ************
/// Cubit: FlutterSound -> WAV -> FFI MEL -> transcribeMel (one-shot)
class VaporRecognizerCubit extends Cubit<VaporRecognizerStates> {
  VaporRecognizerCubit({String? lang})
      : _lang = lang ?? 'ar',
        super(VaporRecognizerInitialState());

  static const MethodChannel _channel = MethodChannel('whisper_onnx');

  final String _lang;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  // streaming capture
  StreamController<Uint8List>? _audioStreamController;
  final BytesBuilder _pcmBuilder = BytesBuilder(copy: false);

  bool _hasMicPermission = false;
  bool isRecognizer = false;

  // audio cfg
  static const int _sampleRate = 16000;
  static const int _numChannels = 1;

  Future<void> initState(bool mounted) async {
    try {
      final mic = await Permission.microphone.request();
      _hasMicPermission = mic.isGranted;
      if (!_hasMicPermission) {
        emit(VaporRecognizerOnErrorRecognitionState('Microphone permission denied'));
        return;
      }

      // Initialize native model once
      await _channel.invokeMethod('initializeModel', {
        'language': _lang,
        'sampleRate': _sampleRate,
        'numChannels': _numChannels,
      });

      await _recorder.openRecorder();
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 80));
    } catch (e) {
      emit(VaporRecognizerOnErrorRecognitionState('initState failed: $e'));
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.inactive) && isRecognizer) {
      await stopRecognizer();
    }
  }

  /// Start recording (buffer PCM16 from FlutterSound)
  Future<void> startRecognizer() async {
    if (!_hasMicPermission) {
      emit(VaporRecognizerOnErrorRecognitionState('Microphone permission denied'));
      return;
    }
    if (isRecognizer) return;

    try {
      try { await _recorder.openRecorder(); } catch (_) {}
      await _audioStreamController?.close();
      _audioStreamController = StreamController<Uint8List>();

      _pcmBuilder.clear();

      _audioStreamController!.stream.listen(
        (chunk) => _pcmBuilder.add(chunk), // PCM16 LE
        onError: (e) => emit(VaporRecognizerOnErrorRecognitionState('audio stream error: $e')),
      );

      await _recorder.startRecorder(
        codec: Codec.pcm16,
        toStream: _audioStreamController!.sink,
        sampleRate: _sampleRate,
        numChannels: _numChannels,
      );

      isRecognizer = true;
      emit(VaporRecognizerOnStartRecognitionState());
    } catch (e) {
      isRecognizer = false;
      emit(VaporRecognizerOnErrorRecognizerStartState());
      emit(VaporRecognizerOnErrorRecognitionState('startRecognizer failed: $e'));
    }
  }

  /// Stop -> write temp WAV -> FFI MEL -> native transcribeMel (one final result)
  Future<void> stopRecognizer() async {
    final wasRunning = isRecognizer;
    isRecognizer = false;

    try { await _recorder.stopRecorder(); } catch (_) {}
    try { await _audioStreamController?.close(); } catch (_) {}
    _audioStreamController = null;

    // grab buffered PCM16
    final Uint8List pcmBytes = _pcmBuilder.toBytes();
    _pcmBuilder.clear();

    try { await _recorder.closeRecorder(); } catch (_) {}

    if (wasRunning) emit(VaporRecognizerOnStopRecognitionState());

    if (pcmBytes.isEmpty) {
      emit(VaporRecognizerOnErrorRecognitionState('No audio captured'));
      return;
    }

    try {
      // 1) Write temp WAV (16kHz/16-bit/mono)
      final wavPath = await _saveAsWav(pcmBytes);

      // 2) Extract MEL via FFI (your existing flow)
      final ptr = wavPath.toNativeUtf8();
      final MelSpectrogramData melDataStruct = extractWhisperFeatures(ptr);
      malloc.free(ptr);

      final int frames = melDataStruct.nFrames;
      final int mels   = melDataStruct.nMels;
      final int total  = frames * mels;
      final Float32List mel = melDataStruct.data.asTypedList(total);

      // 3) Call native once with MEL
      final String? text = await _channel.invokeMethod<String>('transcribeMel', {
        'mel': mel,       // Float32List
        'nFrames': frames
      });

      emit(VaporRecognizerOnResultState(text ?? '', true));
    } catch (e) {
      emit(VaporRecognizerOnErrorRecognitionState('transcribeMel failed: $e'));
    }
  }

  /// ===== Helpers =====

  Future<String> _saveAsWav(Uint8List pcm16le) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'rec.wav');

    const sr = _sampleRate;
    const channels = _numChannels;
    const bits = 16;

    final dataSize = pcm16le.length;
    final byteRate = sr * channels * (bits ~/ 8);
    final fileSize = 36 + dataSize;

    final header = <int>[
      ...ascii.encode('RIFF'),
      ..._le(fileSize, 4),
      ...ascii.encode('WAVE'),
      ...ascii.encode('fmt '),
      ..._le(16, 4),                 // Subchunk1Size (PCM)
      ..._le(1, 2),                  // AudioFormat (PCM)
      ..._le(channels, 2),
      ..._le(sr, 4),
      ..._le(byteRate, 4),
      ..._le((channels * bits) ~/ 8, 2), // BlockAlign
      ..._le(bits, 2),               // BitsPerSample
      ...ascii.encode('data'),
      ..._le(dataSize, 4),
    ];

    final file = File(path);
    await file.writeAsBytes([...header, ...pcm16le], flush: true);
    return path;
  }

  List<int> _le(int v, int bytes) =>
      List.generate(bytes, (i) => (v >> (8 * i)) & 0xFF);
}
