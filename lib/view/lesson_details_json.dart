import 'package:bassem_flutter/vapor_recognizer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:ui' as ui;

import '../widget/lesson_detail_json_card.dart';

class LessonDetailsJsonView extends StatefulWidget {
  const LessonDetailsJsonView({
    super.key,
    required this.name,
    required this.filePath,
  });

  final String name;
  final String filePath;

  @override
  State<LessonDetailsJsonView> createState() => _LessonDetailsJsonState();
}

class _LessonDetailsJsonState extends State<LessonDetailsJsonView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  bool isLoading = false;
  bool isMicActive = false; // UI-only flag

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic(BuildContext context) async {
    final cubit = context.read<VaporRecognizerCubit>(); // ✅ read the Cubit

    // Prevent spamming the button while loading
    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      if (!cubit.isRecognizer) {
        // Start one-shot recording (FlutterSound buffers PCM16)
        await cubit.startRecognizer();
        setState(() => isMicActive = true);
      } else {
        // Stop -> save WAV -> FFI MEL -> transcribeMel -> emit final result
        await cubit.stopRecognizer();
        setState(() => isMicActive = false);
      }
    } finally {
      // small UX delay optional; otherwise remove the delayed block
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => VaporRecognizerCubit()
        ..initState(true), // ✅ initialize model + recorder once
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: PopScope(
          canPop: true,
          onPopInvoked: (didPop) {}, // keep if you need
          child: Scaffold(
            body: BlocListener<VaporRecognizerCubit, VaporRecognizerStates>(
              listener: (context, state) {
                // Keep local UI flags in sync with Cubit states
                if (state is VaporRecognizerOnStartRecognitionState) {
                  setState(() {
                    isMicActive = true;
                  });
                } else if (state is VaporRecognizerOnStopRecognitionState) {
                  setState(() {
                    isMicActive = false;
                  });
                } else if (state is VaporRecognizerOnErrorRecognitionState) {
                  setState(() {
                    isMicActive = false;
                    isLoading = false;
                  });
                  // You can show a SnackBar/Toast here if you want:
                  // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
                } else if (state is VaporRecognizerOnResultState) {
                  // You get the final text here (state.transcript, isFinal=true)
                  // Hook your UI with it (e.g., setState or pass to a controller)
                  // print('Transcript: ${state.transcript}');
                }
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight;
                  // final width  = constraints.maxWidth;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: height * .5,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: 5, // TODO: bind to your real item count
                          itemBuilder: (context, index) {
                            // TODO: bind these to your real data
                            final letter = '';
                            final audio  = '';

                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: LessonDetailJsonCard(
                                letter: letter,
                                audio: audio,
                                isLoading: isLoading,
                                isMicActive: isMicActive,
                                onTap: () => _toggleMic(context), // ✅ hook
                              ),
                            );
                          },
                        ),
                      ),

                      // Optional: a dedicated mic button below the cards
                      // Padding(
                      //   padding: const EdgeInsets.only(top: 12),
                      //   child: ElevatedButton.icon(
                      //     onPressed: () => _toggleMic(context),
                      //     icon: Icon(isMicActive ? Icons.stop : Icons.mic),
                      //     label: Text(isMicActive ? 'إيقاف' : 'تسجيل'),
                      //   ),
                      // ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
