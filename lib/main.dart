import 'package:bassem_flutter/dart_ffi.dart';
import 'package:bassem_flutter/vapor_recognizer_cubit.dart';
import 'package:bassem_flutter/view/lesson_details_json.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadDylib();
  runApp(BlocProvider(
      create: (context) => VaporRecognizerCubit(),
      child: const LessonDetailsJsonView(name: '', filePath: '')));
}
