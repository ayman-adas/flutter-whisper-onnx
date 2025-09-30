import 'package:bassem_flutter/vapor_recognizer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'speak_widget.dart';

class LessonDetailJsonCard extends StatefulWidget {
  final String letter;
  bool isLoading;
  bool isMicActive; // ✅ Track mic state per widget
  final void Function() onTap;
  final String audio;
  LessonDetailJsonCard(
      {super.key,
      required this.letter,
      required this.audio,
      required this.isLoading,
      required this.isMicActive,
      required this.onTap});

  @override
  State<LessonDetailJsonCard> createState() => _LessonDetailJsonCardState();
}

class _LessonDetailJsonCardState extends State<LessonDetailJsonCard> {
  String nResult = '';
  double percent = 0;
  int numOfBadRepetation = 0;
  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final double height = MediaQuery.of(context).size.height;
    String feedback = '';
    MaterialColor color = Colors.amber;

    return BlocConsumer<DeepRecognizerCubit, DeepRecognizerStates>(
        listener: (BuildContext context, DeepRecognizerStates state) {
          if (state is DeepRecognizerOnTranscriptionResultState) {
            nResult = state.transcript ?? '';
            String cleanText(String text) =>
                text.replaceAll('[UNK]', '').toLowerCase().trim().replaceAll(
                    ' ',
                    ''); // Also remove internal spaces if needed              print("my nresult $nResult");
            print("CLEANED nResult: '${cleanText(nResult)}'");
            print("CLEANED letter: '${cleanText(widget.letter)}'");

            double matchPercentage = similarityPercentage(
              cleanText(nResult),
              cleanText(widget.letter),
            );
            percent = matchPercentage;
            print("my nresult $nResult");
            print("my percentage $percent");
            if (numOfBadRepetation >= 3 && percent < 30) {
              percent = 55;
            }
            if (percent < 30) {
              feedback = 'Very Poor (${percent.toStringAsFixed(1)}%)';
              percent = 30;
              color = Colors.red;
              numOfBadRepetation++;
            } else if (percent < 50) {
              feedback = 'Poor (${percent.toStringAsFixed(1)}%)';
              color = Colors.deepOrange;
            } else if (percent < 65) {
              feedback = 'Average (${percent.toStringAsFixed(1)}%)';
              color = Colors.amber;
            } else if (percent < 85) {
              feedback = 'Good (${percent.toStringAsFixed(1)}%)';
              color = Colors.lightGreen;
            } else {
              feedback = 'Excellent (${percent.toStringAsFixed(1)}%)';
              color = Colors.green;
              if (percent > 95) {
                percent = 95;
              }
            }
          } else if (state is DeepRecognizerOnErrorRecognitionState) {}
        },
        builder: (context, state) => SizedBox(
          child: Column(
            children: [
              SizedBox(height: height * 0.01),
        
              /// 🎤 **Card with Speak Button**
              Container(
                height: height * 0.2444,
                width: width * 0.93,
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16))),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      /// 🔠 **Letter Display**
                        Text((widget.letter)),
                      
                      const SizedBox(height: 13),
                    ],
                  ),
                ),
              ),
        
              Padding(
                padding: const EdgeInsets.all(18.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        height: height * 0.0629,
                        width: width * .4,
                        decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius:
                                BorderRadius.all(Radius.circular(16))),
                        child: InkWell(
                          onTap: widget.onTap,
                          child: SpeakWidget(
                            text: widget.letter,
                            isLoading: widget.isLoading,
                            isMicActive: widget.isMicActive,
                            nResult: nResult,
                          ),
                        )),
        
                  
                  ],
                ),
              ),
              Visibility(
                visible:
                    state is DeepRecognizerOnTranscriptionResultState &&
                        nResult != '',
                child: Column(
                  children: [
                    Text("n result :$nResult"),
                    
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}

List<TextSpan> getSpans(String text) {
  final diacritics = RegExp(r'[\u064B-\u066f]');
  List<TextSpan> spans = [];

  for (int i = 0; i < text.length; i++) {
    final char = text[i];

    if (diacritics.hasMatch(char) ||
        ('ۡ ').contains(char) ||
        " ٰ".contains(char) ||
        "آ".contains(char)) {
      spans.add(TextSpan(
          text: char,
          style: TextStyle(
            color: Colors.red,
            fontSize: 50,
          )));
    } else {
      spans.add(
        TextSpan(
            text: char, style: TextStyle(fontSize: 50, color: Colors.black)),
      );
    }
  }

  return spans;
}

int levenshteinDistance(String s, String t) {
  final m = s.length;
  final n = t.length;

  if (m == 0) return n;
  if (n == 0) return m;

  List<List<int>> dp = List.generate(
    m + 1,
    (_) => List<int>.filled(n + 1, 0),
  );

  for (int i = 0; i <= m; i++) dp[i][0] = i;
  for (int j = 0; j <= n; j++) dp[0][j] = j;

  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      int cost = s[i - 1] == t[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1, // deletion
        dp[i][j - 1] + 1, // insertion
        dp[i - 1][j - 1] + cost // substitution
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  return dp[m][n];
}

double similarityPercentage(String a, String b) {
  final distance = levenshteinDistance(a, b);
  final maxLength = a.length > b.length ? a.length : b.length;

  if (maxLength == 0) return 100.0;
  return ((maxLength - distance) / maxLength) * 100;
}
