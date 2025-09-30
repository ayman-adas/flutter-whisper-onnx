import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bassem_flutter/dart_ffi.dart';
import 'package:ffi/ffi.dart';

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import "dart:developer" as developer;

// ************
// TODO: STATES
abstract class DeepRecognizerStates {}

class DeepRecognizerInitialState extends DeepRecognizerStates {}

class DeepRecognizerOnStartRecognitionState extends DeepRecognizerStates {}

class DeepRecognizerOnStopRecognitionState extends DeepRecognizerStates {}

class DeepRecognizerOnErrorRecognitionState extends DeepRecognizerStates {}

class DeepRecognizerOnTranscriptionResultState extends DeepRecognizerStates {
  final String transcript;
  DeepRecognizerOnTranscriptionResultState(this.transcript);
}

// ************
// TODO: CUBIT
class DeepRecognizerCubit extends Cubit<DeepRecognizerStates> {
  DeepRecognizerCubit() : super(DeepRecognizerInitialState()) {
    _initializeWhisper();
  }

  static DeepRecognizerCubit get(context) => BlocProvider.of(context);
  static const MethodChannel _channel = MethodChannel('whisper_onnx');

  Stream? micStream;
  StreamSubscription? micListener;
  BehaviorSubject<List<int>>? micBuffer;
  bool isRecording = false;
  List<int> audioBuffer = [];
  bool _isWhisperInitialized = false;
  bool _isInitializing = false;

  Future<void> _initializeWhisper() async {
    if (_isWhisperInitialized || _isInitializing) return;

    _isInitializing = true;

    try {
      // Optional: init MediaStore (Android). Safe no-op elsewhere.
      
      final String result = await _channel.invokeMethod('initializeModel');
      _isWhisperInitialized = true;
      print('Whisper initialized: $result');
    } catch (e) {
      print('Failed to initialize Whisper: $e');
      emit(DeepRecognizerOnErrorRecognitionState());
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> startRecognizer() async {
    if (isRecording) return;

    var status = await Permission.microphone.request();
    if (status.isDenied) {
      emit(DeepRecognizerOnErrorRecognitionState());
      return;
    }

    micBuffer = BehaviorSubject<List<int>>();
    audioBuffer.clear();

    micStream = await MicStream.microphone(
      sampleRate: 16000,
      channelConfig: ChannelConfig.CHANNEL_IN_MONO,
      audioFormat: AudioFormat.ENCODING_PCM_16BIT,
    );

    micListener = micStream!.listen((buffer) {
      if (isRecording) {
        audioBuffer.addAll(buffer);
      }
    });

    isRecording = true;
    emit(DeepRecognizerOnStartRecognitionState());
  }

  Future<void> stopRecognizer() async {
    if (!isRecording) return;

    await micListener?.cancel();
    isRecording = false;

    if (audioBuffer.isEmpty) {
      emit(DeepRecognizerOnErrorRecognitionState());
      return;
    }

    String wavFile = await _saveAsWav(audioBuffer);
    await _transcribe(wavFile);
  }

  Future<String> _saveAsWav(List<int> audioData) async {
    Directory tempDir = await getTemporaryDirectory();
    String filePath = join(tempDir.path, "audio.wav");
    File file = File(filePath);

    // WAV Header (PCM 16-bit, 16kHz, Mono)
    int sampleRate = 16000;
    int byteRate = sampleRate * 2;
    int fileSize = audioData.length + 36;
    List<int> wavHeader = [
      ...ascii.encode("RIFF"),
      ..._intToBytes(fileSize, 4),
      ...ascii.encode("WAVE"),
      ...ascii.encode("fmt "),
      ..._intToBytes(16, 4),
      ..._intToBytes(1, 2),
      ..._intToBytes(1, 2),
      ..._intToBytes(sampleRate, 4),
      ..._intToBytes(byteRate, 4),
      ..._intToBytes(2, 2),
      ..._intToBytes(16, 2),
      ...ascii.encode("data"),
      ..._intToBytes(audioData.length, 4),
    ];

    await file.writeAsBytes([...wavHeader, ...audioData]);

    // try {
    //   await MediaStore.ensureInitialized();
    //   MediaStore.appFolder = 'ayman'; // subfolder
    //   final ms = MediaStore();

    //   final id = await ms.saveFile(
    //     tempFilePath: filePath,
    //     dirType: DirType.audio,
    //     dirName: DirName.music, // => /Download/ayman/Recordings
    //   );
    // } catch (e) {
    //   print('MediaStore save failed: $e');
    // }x

    return filePath;
  }

  List<int> logitsToTokenIds(List<List<List<double>>> logits) {
    List<int> tokenIds = [];

    // Assuming logits shape is [batch_size, sequence_length, vocab_size]
    for (var sequence in logits[0]) {
      // First batch
      int maxIndex = 0;
      double maxValue = sequence[0];

      // Find the index of the maximum value (argmax)
      for (int i = 1; i < sequence.length; i++) {
        if (sequence[i] > maxValue) {
          maxValue = sequence[i];
          maxIndex = i;
        }
      }
      tokenIds.add(maxIndex); // The maxIndex represents the most likely token
    }
    return tokenIds;
  }

  late Map<int, String> vocab;

  // Improved version of loadVocab function with error handling
  Future<void> loadVocab() async {
    try {
      final String vocabJson = await rootBundle.loadString('assets/vocab.json');
      final Map<String, dynamic> raw = jsonDecode(vocabJson);
      vocab = raw.map((key, value) => MapEntry(value as int, key));
    } catch (e) {
      print("Error loading vocab: $e");
    }
  }

  Future<String> decodeTokenIds(List<int> ids, String filePath) async {
    // Read the file content
    DateTime start = DateTime.now();

    final jsonString = await rootBundle.loadString(filePath);

    // Decode original vocab: string -> ID
    final Map<String, dynamic> originalVocab = jsonDecode(jsonString);

    // Reverse it: ID string -> token string
    final Map<String, String> reversedVocab = {
      for (var entry in originalVocab.entries) entry.value.toString(): entry.key
    };

    // Convert token IDs to string
    final buffer = StringBuffer();
    for (final id in ids) {
      final key = id.toString();
      if (reversedVocab.containsKey(key)) {
        buffer.write(reversedVocab[key]);
      } else {
        buffer.write('[UNK]');
      }
    }
    final byteValues = <int>[];
    final problematicChars = <String>[];
    final inputString = buffer.toString();
    print("Decoding string: '$inputString'");
    print("-" * 20);
    final charToByteMap = getCharToByteMap();

    // Iterate through the runes (Unicode code points) of the string
    for (final rune in inputString.runes) {
      final char =
          String.fromCharCode(rune); // Convert rune back to String character
      if (charToByteMap.containsKey(char)) {
        final byteValue =
            charToByteMap[char]!; // Use ! assuming key exists check
        byteValues.add(byteValue);
        print("Char '$char' (rune=$rune) -> Byte $byteValue");
      } else {
        // This character is not part of the standard byte mapping
        problematicChars.add(char);
        print("Char '$char' (rune=$rune) -> Not found in standard byte map!");
      }
    }

    if (problematicChars.isNotEmpty) {
      print(
          "\nWarning: The following characters were not found in the standard byte map: $problematicChars");
      print(
          "This might indicate they are special tokens, multi-character tokens, or the string uses a non-standard mapping.");
    }

    // Assemble the byte sequence using Uint8List for efficiency
    final byteSequence = Uint8List.fromList(byteValues);
    print("-" * 20);
    print("Resulting Byte Values: $byteValues");
    print("Resulting Byte Sequence (Uint8List): $byteSequence");
    // Print hex representation for comparison with Python output
    print(
        "Hex representation: ${byteSequence.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
    print("-" * 20);

    // Attempt to decode using UTF-8
    try {
      // allowMalformed: true replaces invalid sequences with the Unicode replacement character (U+FFFD, '')
      final decodedText = utf8.decode(byteSequence, allowMalformed: true);
      print("Decoded Text (UTF-8, errors replaced): '$decodedText'");

      // You could try without allowMalformed: true to see the strict error
      // final decodedTextStrict = utf8.decode(byteSequence);
      // print("Decoded Text (UTF-8, strict): '$decodedTextStrict'");
      print(
          "Decoding took: ${DateTime.now().difference(start).inMilliseconds} ms");
      return decodedText;
    } on FormatException catch (e) {
      // Catching FormatException which is thrown by utf8.decode on errors when allowMalformed is false
      print("\n--- UTF-8 Decoding Error ---");
      print("Error: $e");
      // Note: Dart's FormatException might not provide the same level of detail
      // about the problematic byte/position as Python's UnicodeDecodeError directly.
      // Using allowMalformed: true is often the more practical approach.
      print(
          "The byte sequence constructed from the input string is not valid UTF-8.");
      return "Decoding Error: $e";
    } catch (e) {
      // Catch any other unexpected errors
      print("\n--- An Unexpected Error Occurred During Decoding ---");
      print("Error: $e");
      return "Decoding Error: $e";
    }
  }

// Generates the standard mapping from byte values (0-255) to
// unique Unicode characters used by tokenizers like GPT-2/Whisper.
  Map<int, String> bytesToUnicode() {
    final bs = <int>[];

    // Add printable ASCII (! to ~)
    for (int i = '!'.codeUnitAt(0); i <= '~'.codeUnitAt(0); i++) {
      bs.add(i);
    }
    // Add extended Latin-1 range (¡ to ¬)
    for (int i = '¡'.codeUnitAt(0); i <= '¬'.codeUnitAt(0); i++) {
      bs.add(i);
    }
    // Add extended Latin-1 range (® to ÿ)
    for (int i = '®'.codeUnitAt(0); i <= 'ÿ'.codeUnitAt(0); i++) {
      bs.add(i);
    }

    final cs = List<int>.from(bs); // Copy initial characters codes

    int n = 0;
    // Assign unique Unicode code points >= 256 for bytes not already covered
    for (int b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }

    // Create the final map: byte value -> character string
    final byteToCharMap = <int, String>{};
    for (int i = 0; i < bs.length; i++) {
      byteToCharMap[bs[i]] = String.fromCharCode(cs[i]);
    }

    return byteToCharMap;
  }

// Generates the inverse map: Unicode character -> byte value (0-255)
  Map<String, int> getCharToByteMap() {
    final byteToChar = bytesToUnicode();
    // Invert the dictionary
    final charToByte = <String, int>{};
    byteToChar.forEach((byteValue, char) {
      charToByte[char] = byteValue;
    });
    return charToByte;
  }

  Float32List bytesPcm16ToFloat32(Uint8List bytesLE) {
    // 2 bytes per sample, little-endian signed
    final sampleCount = bytesLE.length ~/ 2;
    final floats = Float32List(sampleCount);
    final bd = ByteData.sublistView(bytesLE);
    for (var i = 0; i < sampleCount; i++) {
      final s = bd.getInt16(i * 2, Endian.little); // [-32768, 32767]
      floats[i] = (s == -32768) ? -1.0 : (s / 32767.0);
    }
    return floats;
  }

// audioBuffer is your List<int> collected from the mic
  Future<String> transcribeFromMicBytes(List<int> audioBuffer) async {
    final pcmF32 = bytesPcm16ToFloat32(Uint8List.fromList(audioBuffer));
    // Send Float32List -> Kotlin receives FloatArray
    final text = await _channel.invokeMethod<String>('transcribeAudio', {
      'audioData': pcmF32,
    });
    emit(DeepRecognizerOnTranscriptionResultState(text ?? 'not found'));
    return text ?? '';
  }

  // FIXED: Convert Pointer to Float32List before sending through method channel
  Future<void> _transcribe(String file) async {
    DateTime start = DateTime.now();
    emit(DeepRecognizerOnStartRecognitionState());

    try {
      await loadVocab(); // Ensure vocab is loaded

      // Start recording and process audio
      print('WAV file path: $file');
      print('File exists: ${File(file).existsSync()}');
      print('File size: ${File(file).lengthSync()} bytes');

      final wavPointer = file.toNativeUtf8();
      print('Native path pointer created');

      MelSpectrogramData   result = extractWhisperFeatures(wavPointer);
      print('FFI call completed');
      final numFrames = result.nFrames;
      final numMels = result.nMels;
      final dataPtr = result.data;

      // CRITICAL FIX: Convert Pointer to Float32List
      // The result.data is a Pointer<Float>, we need to convert it to Float32List
      final int totalElements = numFrames * numMels;
      final Float32List melData = dataPtr.asTypedList(totalElements);

      print(
          'Extracted mel spectrogram: frames=$numFrames, mels=$numMels, total_elements=$totalElements');

      // Now send the Float32List (not the Pointer) through the method channel
      String results = (await _channel.invokeMethod<String>('transcribeMel', {
            'mel': melData, // Float32List instead of Pointer
            'nFrames': numFrames,
          })) ??
          '';

      print('Transcription completed: $results');
      print(
          'Total processing time: ${DateTime.now().difference(start).inMilliseconds} ms');

      emit(DeepRecognizerOnTranscriptionResultState(results));
    } catch (e) {
      print('Transcription error: $e');
      emit(DeepRecognizerOnErrorRecognitionState());
    }
  }

  List<int> _intToBytes(int value, int length) {
    return List.generate(length, (i) => (value >> (8 * i)) & 0xFF);
  }
}
