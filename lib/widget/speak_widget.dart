import 'package:bassem_flutter/vapor_recognizer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SpeakWidget extends StatefulWidget {
  final String text;
  String nResult;
  bool isMicActive; // ✅ Track mic state per widget
  bool isLoading;

  SpeakWidget(
      {super.key,
      required this.text,
      required this.isLoading,
      required this.isMicActive,
      required this.nResult});

  @override
  State<SpeakWidget> createState() => _SpeakWidgetState();
}

class _SpeakWidgetState extends State<SpeakWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeepRecognizerCubit, DeepRecognizerStates>(
      listener: (BuildContext context, DeepRecognizerStates state) {
        // if (state is DeepRecognizerOnTranscriptionResultState) {
        //   widget.nResult = state.transcript ?? '';
        //   if (widget.nResult.isNotEmpty &&
        //       removeDiacritics(widget.nResult)
        //           .contains(removeDiacritics(widget.text))) {
        //     showToast(
        //       text: LocalizationString.yourReadIsCorrect,
        //       state: AlertStates.SUCCESS,
        //       primaryColor: AppColors.green,
        //     );
        //   } else {
        //     showToast(
        //       text: LocalizationString.yourReadIsFailed + widget.nResult,
        //       state: AlertStates.ERROR,
        //       primaryColor: AppColors.red,
        //     );
        //     widget.nResult = '';
        //   }
        // } else if (state is DeepRecognizerOnErrorRecognitionState) {}
      },
      builder: (BuildContext context, DeepRecognizerStates state) {
        return widget.isLoading?Center(child: CircularProgressIndicator()): Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: SizedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isMicActive ? Icons.stop : Icons.keyboard_voice,
                  color: widget.isMicActive ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  "speak",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .copyWith(color: Colors.blue),
                ),

              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}
