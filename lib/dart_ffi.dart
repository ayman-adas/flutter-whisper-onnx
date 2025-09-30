import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

base class MelSpectrogramData extends Struct {
  external Pointer<Float> data;

  @Uint64()
  external int nFrames;

  @Uint64()
  external int nMels;
}

typedef ExtractWhisperFeaturesC = MelSpectrogramData Function(Pointer<Utf8>);
typedef ExtractWhisperFeaturesDart = MelSpectrogramData Function(Pointer<Utf8>);

typedef FreeSpectrogramDataC = Void Function(MelSpectrogramData);
typedef FreeSpectrogramDataDart = void Function(MelSpectrogramData);

late ExtractWhisperFeaturesDart extractWhisperFeatures;
late FreeSpectrogramDataDart freeSpectrogramData;

Future<void> loadDylib() async {
  print("/////////////////////// loadDylib /////////////////////// ");
  if (Platform.isIOS) {
    print("dyLibPath loadDylib");
    final executable = File(Platform.executable);
    print("dyLibPath executable $executable");
    final dyLibPath = '${executable.parent.path}/Frameworks/libmel_feature_extractor_rust.dylib';
    print("dyLibPath path Found !! ${dyLibPath}");
    final DynamicLibrary dylib = Platform.isIOS ? DynamicLibrary.open(dyLibPath) : DynamicLibrary.process();
    extractWhisperFeatures = dylib.lookupFunction<ExtractWhisperFeaturesC, ExtractWhisperFeaturesDart>(
      'extract_whisper_features',
    );

    freeSpectrogramData = dylib.lookupFunction<FreeSpectrogramDataC, FreeSpectrogramDataDart>(
      'free_spectrogram_data',
    );
  } else {
    final dylib =
        Platform.isAndroid ? DynamicLibrary.open('libmel_feature_extractor_rust.so') : DynamicLibrary.open("libmel_feature_extractor_rust.dylib");

    extractWhisperFeatures = dylib.lookupFunction<ExtractWhisperFeaturesC, ExtractWhisperFeaturesDart>(
      'extract_whisper_features',
    );

    freeSpectrogramData = dylib.lookupFunction<FreeSpectrogramDataC, FreeSpectrogramDataDart>(
      'free_spectrogram_data',
    );
  }
}
