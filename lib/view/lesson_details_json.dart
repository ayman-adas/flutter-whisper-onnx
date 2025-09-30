import 'package:bassem_flutter/vapor_recognizer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:ui' as ui;
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import '../widget/lesson_detail_json_card.dart';

class LessonDetailsJsonView extends StatefulWidget {
  const LessonDetailsJsonView(
      {super.key, required this.name, required this.filePath});
  final String name;
  final String filePath;
  @override
  State<LessonDetailsJsonView> createState() => _LessonDetailsJsonState();
}

class _LessonDetailsJsonState extends State<LessonDetailsJsonView> {
  PageController _pageController = PageController();
  int _currentPage = 0;
  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      int page = _pageController.page?.round() ?? 0;
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

  bool isLoading = false;
  bool isMicActive = false; // ✅ Track mic state per widget

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height;
    final double width = MediaQuery.of(context).size.width;

    return BlocProvider(
        create: (BuildContext context) => DeepRecognizerCubit(),
        child: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: PopScope(
                onPopInvoked: (didPop) {},
                child: Scaffold(
                   
                    body: Container(
                        padding: EdgeInsets.all(0),
                        margin: EdgeInsets.zero,
                        decoration: BoxDecoration(
                            image: DecorationImage(
                                image: AssetImage(
                                  'assets/images/lesson_json.png',
                                ),
                                fit: BoxFit.fill)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: height * .5,
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: 5,
                                itemBuilder: (context, index) {
                                  final category = '';
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: LessonDetailJsonCard(
                                      letter: '' ?? '',
                                      audio: '' ?? '',
                                      isLoading: isLoading,
                                      isMicActive: isMicActive,
                                      onTap: () async {
                                        final recognizerCubit =
                                            context.read<DeepRecognizerCubit>();

                                        // Prevent multiple mic activations
                                        if (recognizerCubit.isRecording &&
                                            !isMicActive) {}

                                        if (!isMicActive &&
                                            !recognizerCubit.isRecording) {
                                          await recognizerCubit
                                              .startRecognizer();
                                          setState(() {
                                            isLoading = true;

                                            Future.delayed(Duration(seconds: 1),
                                                () {
                                              setState(() {
                                                isLoading = false;
                                              });
                                            });
                                            isMicActive = true;
                                          });
                                        } else {
                                          isLoading = true;
                                          isMicActive = false;

                                          setState(() {});
                                          await recognizerCubit
                                              .stopRecognizer();
                                          Future.delayed(Duration(seconds: 1),
                                              () {
                                            isLoading = false;
                                            setState(() {});
                                          });
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                       
                          ],
                        ))))));
  }
}
