import 'strings_bn.dart';

/// App language: English (the text in the code) or Bangla.
///
/// Screens write their text in English through [tr]; in Bangla the same key
/// is looked up in [bnStrings]. Placeholders such as `{n}` are filled from
/// [args] (numbers in Bangla digits). Text that has no translation yet stays
/// in English rather than breaking.
String _language = 'en';

String get appLanguage => _language;
bool get isBangla => _language == 'bn';

/// Called by the session when the person picks a language.
void setAppLanguage(String code) => _language = code == 'bn' ? 'bn' : 'en';

String tr(String text, [Map<String, Object?> args = const {}]) {
  var out = isBangla ? (bnStrings[text] ?? text) : (_enStrings[text] ?? text);
  args.forEach((key, value) {
    final filled = value is Raw ? value.text : localDigits('${value ?? ''}');
    out = out.replaceAll('{$key}', filled);
  });
  return out;
}

/// English for keys that are not English text: "@…" names a word that means
/// different things in different places (Bangla needs a different word each).
const _enStrings = {
  '@payment_due': 'Due',
};

/// A [tr] argument inserted exactly as it is: digits are not turned into
/// Bangla digits (codes, passwords, links and addresses people copy or type).
class Raw {
  const Raw(this.text);
  final String text;
}

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// "12/12" -> "১২/১২" in Bangla; unchanged in English.
String localDigits(String text) {
  if (!isBangla) return text;
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    buffer.write(unit >= 48 && unit <= 57 ? _bnDigits[unit - 48] : String.fromCharCode(unit));
  }
  return buffer.toString();
}

const _bnDays = {
  'Saturday': 'শনিবার',
  'Sunday': 'রবিবার',
  'Monday': 'সোমবার',
  'Tuesday': 'মঙ্গলবার',
  'Wednesday': 'বুধবার',
  'Thursday': 'বৃহস্পতিবার',
  'Friday': 'শুক্রবার',
};

const _bnDaysShort = {
  'Saturday': 'শনি',
  'Sunday': 'রবি',
  'Monday': 'সোম',
  'Tuesday': 'মঙ্গল',
  'Wednesday': 'বুধ',
  'Thursday': 'বৃহঃ',
  'Friday': 'শুক্র',
};

/// A weekday ("Saturday") for display: "Sat"/"Saturday", or "শনি"/"শনিবার".
String dayLabel(String englishDay, {bool short = true}) {
  if (englishDay.isEmpty) return englishDay;
  if (isBangla) return (short ? _bnDaysShort : _bnDays)[englishDay] ?? englishDay;
  return short && englishDay.length > 3 ? englishDay.substring(0, 3) : englishDay;
}

/// The intl locale for dates and numbers.
String get intlLocale => isBangla ? 'bn' : 'en';
