import 'dart:developer';

import 'package:bassem_flutter/ascii.dart';


class ArabicText {
  final List<int> SYMBOL = [
    ASCII.Ba,
    ASCII.Hamza,
    ASCII.AlifWithHamzaAbove,
    ASCII.WawWithHamzaAbove,
    ASCII.AlifWithHamzaBelow,
    ASCII.YaWithHamzaAbove,
    ASCII.Alif,
    ASCII.AlifWithHamzatWasl,
    ASCII.AlifWithMaddah,
    ASCII.TaMarbuta,
    ASCII.Ta,
    ASCII.Tha,
    ASCII.Jeem,
    ASCII.HHa,
    ASCII.Kha,
    ASCII.Dal,
    ASCII.Thal,
    ASCII.Ra,
    ASCII.Zain,
    ASCII.Seen,
    ASCII.Sheen,
    ASCII.Sad,
    ASCII.DDad,
    ASCII.TTa,
    ASCII.DTha,
    ASCII.Ain,
    ASCII.Ghain,
    ASCII.Fa,
    ASCII.Qaf,
    ASCII.Kaf,
    ASCII.Lam,
    ASCII.Meem,
    ASCII.Noon,
    ASCII.Ha,
    ASCII.Waw,
    ASCII.AlifMaksura,
    ASCII.Ya,
    ASCII.Space
  ];

  String words;

  ArabicText(this.words);

  String toCharactersWithoutDiacritics() {
    if (words == null) return "";
    if (words.trim().length == 0) return "";

    String nWords = "";
    words.runes.forEach((int rune) {
      if (SYMBOL.contains(rune)) {
        var nCharacter = new String.fromCharCode(rune);
        nWords += nCharacter;
      } else if (!(rune == 8207 || rune == 48 || rune == 49)) {
        // 8207
        // 48
        // 49
log('****************************************');
log('****************************************');
log('****************************************');
log('Missing Character : ${String.fromCharCode(rune)}');
log('ASCII : $rune');
log('Please Call me 0799599100');
log('****************************************');
log('****************************************');
      }
    });

    return nWords;
    // TODO return new SearchText().cleanup(nWords, false);
  }
}

// main() {
//   String TestStr = "أدعية النَّبِيِّ صَلَّى اللهُ عَلَيْهِ وَسَلَّمَ";
//   print(ArabicText(TestStr).toArabicCharactersWithoutDiacritics());
// }
