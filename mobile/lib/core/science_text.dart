/// Science and maths text that arrives from other places (ChatGPT, Word,
/// Google Docs, websites, PDFs) made to show the way it looked there.
///
/// The same rules live on the website (frontend/src/utils/scienceText.js);
/// keep the two in step.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '−': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
};
const _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '−': '₋', '=': '₌', '(': '₍', ')': '₎',
  'a': 'ₐ', 'e': 'ₑ', 'o': 'ₒ', 'x': 'ₓ', 'h': 'ₕ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'p': 'ₚ', 's': 'ₛ', 't': 'ₜ',
};
final _fromSuperscript = {
  for (final e in _superscripts.entries)
    if (e.key != '−') e.value: e.key,
};
final _fromSubscript = {
  for (final e in _subscripts.entries)
    if (e.key != '−') e.value: e.key,
};

String? _mapAll(String text, Map<String, String> table) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = table[ch];
    if (mapped == null) return null;
    out.write(mapped);
  }
  return out.toString();
}

/// "2" -> "²", "-3" -> "⁻³"; null when a character has no superscript form.
String? toSuperscript(String text) => text.trim().isEmpty ? null : _mapAll(text.trim(), _superscripts);

/// "2" -> "₂"; null when a character has no subscript form.
String? toSubscript(String text) => text.trim().isEmpty ? null : _mapAll(text.trim(), _subscripts);

/// Text that was raised (sup) or lowered (sub) in the source, kept readable as plain text.
String scriptText(String text, {required bool superscript}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return '';
  final unicode = superscript ? toSuperscript(clean) : toSubscript(clean);
  if (unicode != null) return unicode;
  return superscript ? '\\({}^{\\text{$clean}}\\)' : '\\({}_{\\text{$clean}}\\)';
}

// Unicode symbols as LaTeX commands, for inside formulas.
const _unicodeTex = {
  '−': '-', '–': '-', '×': r'\times ', '÷': r'\div ', '·': r'\cdot ', '⋅': r'\cdot ', '∙': r'\cdot ',
  '≤': r'\le ', '≥': r'\ge ', '≠': r'\neq ', '±': r'\pm ', '∓': r'\mp ', '≈': r'\approx ', '≡': r'\equiv ',
  '∼': r'\sim ', '≅': r'\cong ', '∝': r'\propto ', '∞': r'\infty ', '→': r'\rightarrow ', '←': r'\leftarrow ',
  '↔': r'\leftrightarrow ', '⇌': r'\rightleftharpoons ', '⇒': r'\Rightarrow ', '⇔': r'\Leftrightarrow ',
  '↑': r'\uparrow ', '↓': r'\downarrow ', '°': r'^\circ ', '∠': r'\angle ', '△': r'\triangle ',
  '∴': r'\therefore ', '∵': r'\because ', '∑': r'\sum ', '∏': r'\prod ', '∫': r'\int ', '∮': r'\oint ',
  '∂': r'\partial ', '∇': r'\nabla ', '∈': r'\in ', '∉': r'\notin ', '⊂': r'\subset ', '⊆': r'\subseteq ',
  '∪': r'\cup ', '∩': r'\cap ', '∅': r'\emptyset ', '∀': r'\forall ', '∃': r'\exists ', '∥': r'\parallel ',
  '⊥': r'\perp ', '′': "'", '″': "''", '…': r'\ldots ', '⋯': r'\cdots ', 'ℏ': r'\hbar ', 'Å': r'\text{Å}',
  'α': r'\alpha ', 'β': r'\beta ', 'γ': r'\gamma ', 'δ': r'\delta ', 'ε': r'\varepsilon ', 'ϵ': r'\epsilon ',
  'ζ': r'\zeta ', 'η': r'\eta ', 'θ': r'\theta ', 'ϑ': r'\vartheta ', 'ι': r'\iota ', 'κ': r'\kappa ',
  'λ': r'\lambda ', 'μ': r'\mu ', 'µ': r'\mu ', 'ν': r'\nu ', 'ξ': r'\xi ', 'π': r'\pi ', 'ρ': r'\rho ',
  'σ': r'\sigma ', 'τ': r'\tau ', 'υ': r'\upsilon ', 'φ': r'\phi ', 'ϕ': r'\phi ', 'χ': r'\chi ', 'ψ': r'\psi ',
  'ω': r'\omega ', 'Γ': r'\Gamma ', 'Δ': r'\Delta ', '∆': r'\Delta ', 'Θ': r'\Theta ', 'Λ': r'\Lambda ',
  'Ξ': r'\Xi ', 'Π': r'\Pi ', 'Σ': r'\Sigma ', 'Υ': r'\Upsilon ', 'Φ': r'\Phi ', 'Ψ': r'\Psi ', 'Ω': r'\Omega ',
  '\u2126': r'\Omega ', '½': r'\frac{1}{2}', '⅓': r'\frac{1}{3}', '⅔': r'\frac{2}{3}', '¼': r'\frac{1}{4}', '¾': r'\frac{3}{4}',
  '\u00a0': ' ', '\u200b': '',
};
const _textCommands = {'text', 'textrm', 'textbf', 'textit', 'mbox', 'mathrm', 'operatorname'};

final _commandName = RegExp(r'^\\([a-zA-Z]+)');
final _letter = RegExp(r'[A-Za-z]');

/// Index just past the group that starts at [start] ("{…}" with nesting), or -1.
int _groupEnd(String source, int start) {
  if (start >= source.length || source[start] != '{') return -1;
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final ch = source[i];
    if (ch == r'\') {
      i++;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

/// Unicode maths symbols inside a formula as LaTeX commands (text groups are left alone).
String unicodeToTex(String tex) {
  final out = StringBuffer();
  var i = 0;
  while (i < tex.length) {
    final ch = tex[i];
    if (ch == r'\') {
      final name = _commandName.firstMatch(tex.substring(i));
      if (name != null && _textCommands.contains(name[1])) {
        var j = i + name[0]!.length;
        while (j < tex.length && tex[j] == ' ') {
          j++;
        }
        final end = _groupEnd(tex, j);
        if (end > 0) {
          out.write(tex.substring(i, end));
          i = end;
          continue;
        }
      }
      final step = name != null ? name[0]!.length : 2;
      out.write(tex.substring(i, i + step > tex.length ? tex.length : i + step));
      i += step;
      continue;
    }
    // A run of superscript or subscript characters: x² -> x^{2}.
    final table = _fromSuperscript.containsKey(ch)
        ? _fromSuperscript
        : _fromSubscript.containsKey(ch)
            ? _fromSubscript
            : null;
    if (table != null) {
      final run = StringBuffer();
      while (i < tex.length && table.containsKey(tex[i])) {
        run.write(table[tex[i]]);
        i++;
      }
      out.write('${identical(table, _fromSuperscript) ? '^' : '_'}{$run}');
      continue;
    }
    if (ch == '√') {
      // √2, √x, √(b²−4ac) -> \sqrt{…}
      var j = i + 1;
      while (j < tex.length && tex[j] == ' ') {
        j++;
      }
      var radicand = '';
      if (j < tex.length && (tex[j] == '(' || tex[j] == '{')) {
        final open = tex[j];
        final close = open == '(' ? ')' : '}';
        var depth = 0;
        var k = j;
        for (; k < tex.length; k++) {
          if (tex[k] == open) {
            depth++;
          } else if (tex[k] == close) {
            depth--;
            if (depth == 0) break;
          }
        }
        if (k < tex.length) {
          radicand = tex.substring(j + 1, k);
          j = k + 1;
        }
      } else {
        final run = RegExp(r'^[A-Za-z0-9.]+').firstMatch(tex.substring(j));
        if (run != null) {
          radicand = run[0]!;
          j += radicand.length;
        }
      }
      out.write(radicand.isNotEmpty ? '\\sqrt{${unicodeToTex(radicand)}}' : r'\sqrt{}');
      i = j;
      continue;
    }
    out.write(_unicodeTex[ch] ?? ch);
    i++;
  }
  return out.toString();
}

// ── Chemistry: \ce{…} (mhchem), which the formula renderer does not have ─────

String _ceSpecies(String token) {
  if (token == '+') return '+';
  final out = StringBuffer();
  var i = 0;
  final coefficient = RegExp(r'^(\d+(?:/\d+)?|\d*\.\d+)(?=[A-Z(\[])').firstMatch(token);
  if (coefficient != null) {
    out.write('${coefficient[1]}\\,');
    i = coefficient[1]!.length;
  }
  final body = StringBuffer();
  while (i < token.length) {
    final rest = token.substring(i);
    RegExpMatch? m;
    if ((m = RegExp(r'^\^\{([^}]*)\}').firstMatch(rest)) != null || (m = RegExp(r'^\^(\d*[+-]|\d+)').firstMatch(rest)) != null) {
      body.write('^{${m![1]}}');
    } else if ((m = RegExp(r'^(\d*[+-])$').firstMatch(rest)) != null && body.isNotEmpty) {
      // A charge at the end without a caret: Cu2+, Cl-
      body.write('^{${m![1]}}');
    } else if ((m = RegExp(r'^\((s|l|g|aq)\)').firstMatch(rest)) != null) {
      body.write('\\,\\mathrm{(${m![1]})}');
    } else if ((m = RegExp(r'^\d+').firstMatch(rest)) != null) {
      body.write('_{${m![0]}}');
    } else if ((m = RegExp(r'^[A-Z][a-z]*').firstMatch(rest)) != null) {
      body.write('\\mathrm{${m![0]}}');
    } else if ((m = RegExp(r'^[.*·]').firstMatch(rest)) != null) {
      body.write(r'\cdot ');
    } else {
      body.write(rest[0]);
      i += 1;
      continue;
    }
    i += m![0]!.length;
  }
  out.write(body);
  return out.toString();
}

/// "2H2 + O2 -> 2H2O" (mhchem) as plain LaTeX.
String ceToTex(String formula) {
  var text = formula.trim();
  // An arrow with something written over it: ->[\Delta]
  text = text.replaceAllMapped(RegExp(r'->\[([^\]]*)\]'), (m) => ' \\xrightarrow{${m[1]}} ');
  text = text
      .replaceAll(RegExp(r'<=>|<-->|⇌'), r' \rightleftharpoons ')
      .replaceAll(RegExp(r'<->|↔'), r' \leftrightarrow ')
      .replaceAll(RegExp(r'->|→'), r' \rightarrow ')
      .replaceAll(RegExp(r'<-|←'), r' \leftarrow ');
  return text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).map((token) {
    if (token.startsWith(r'\')) return token;
    if (token == '^') return r'\uparrow';
    if (token == 'v') return r'\downarrow';
    return _ceSpecies(token);
  }).join(' ');
}

/// Replaces \name{…} (balanced; [args] groups) everywhere with `convert(arguments)`.
String _replaceCommand(String tex, String name, String Function(List<String> args) convert, {int args = 1}) {
  final pattern = RegExp('\\\\$name(?![a-zA-Z])\\s*');
  final out = StringBuffer();
  var cursor = 0;
  var from = 0;
  while (true) {
    final match = pattern.firstMatch(tex.substring(from));
    if (match == null) break;
    final start = from + match.start;
    var j = from + match.end;
    final values = <String>[];
    for (var a = 0; a < args; a++) {
      while (j < tex.length && tex[j] == ' ') {
        j++;
      }
      final end = _groupEnd(tex, j);
      if (end < 0) break;
      values.add(tex.substring(j + 1, end - 1));
      j = end;
    }
    if (values.length < args) {
      from = from + match.end;
      continue;
    }
    out
      ..write(tex.substring(cursor, start))
      ..write(convert(values));
    cursor = j;
    from = j;
  }
  out.write(tex.substring(cursor));
  return out.toString();
}

/// A formula copied from ChatGPT, Overleaf or a textbook, cleaned up so the
/// formula renderer understands it: chemistry (\ce, \pu), units (\si, \SI,
/// \qty), numbered environments, labels, and Unicode symbols.
String prepareTex(String tex) {
  var out = tex
      .replaceAll(RegExp(r'\\label\{[^}]*\}|\\tag\*?\{[^}]*\}|\\nonumber|\\notag'), '')
      .replaceAll(RegExp(r'\\begin\{(align|eqnarray)\*?\}'), r'\begin{aligned}')
      .replaceAll(RegExp(r'\\end\{(align|eqnarray)\*?\}'), r'\end{aligned}')
      .replaceAll(RegExp(r'\\begin\{gather\*?\}'), r'\begin{gathered}')
      .replaceAll(RegExp(r'\\end\{gather\*?\}'), r'\end{gathered}')
      .replaceAll(RegExp(r'\\(?:begin|end)\{(?:equation|displaymath|math)\*?\}'), '')
      .replaceAll(RegExp(r'\\lt(?![a-zA-Z])'), '<')
      .replaceAll(RegExp(r'\\gt(?![a-zA-Z])'), '>')
      .replaceAll(RegExp(r'\\celsius(?![a-zA-Z])'), r'^\circ\mathrm{C}');
  out = _replaceCommand(out, 'ce', (a) => ceToTex(a[0]));
  out = _replaceCommand(out, 'pu', (a) => '\\mathrm{${a[0]}}');
  out = _replaceCommand(out, 'SI', (a) => '${a[0]}\\,\\mathrm{${a[1]}}', args: 2);
  out = _replaceCommand(out, 'qty', (a) => '${a[0]}\\,\\mathrm{${a[1]}}', args: 2);
  out = _replaceCommand(out, 'si', (a) => '\\mathrm{${a[0]}}');
  out = _replaceCommand(out, 'unit', (a) => '\\mathrm{${a[0]}}');
  out = _replaceCommand(out, 'textsuperscript', (a) => '^{\\text{${a[0]}}}');
  out = _replaceCommand(out, 'textsubscript', (a) => '_{\\text{${a[0]}}}');
  return unicodeToTex(out).trim();
}

// ── A formula as readable plain text (when it cannot be typeset) ─────────────

final Map<String, String> _texSymbols = {
  for (final e in _unicodeTex.entries)
    if (RegExp(r'^\\[a-zA-Z]+ $').hasMatch(e.value)) e.value.trim().substring(1): e.key,
  'le': '≤', 'leq': '≤', 'ge': '≥', 'geq': '≥', 'ne': '≠', 'to': '→', 'circ': '°', 'degree': '°',
  'epsilon': 'ε', 'cdots': '⋯', 'ldots': '…', 'quad': ' ', 'qquad': '  ',
};

/// "x^{2}+\frac{1}{2}" -> "x²+(1)/(2)": readable when the formula cannot be typeset.
String texToPlain(String tex) {
  var out = prepareTex(tex);
  for (var pass = 0; pass < 4; pass++) {
    for (final name in ['frac', 'dfrac', 'tfrac']) {
      out = _replaceCommand(out, name, (a) => '(${a[0]})/(${a[1]})', args: 2);
    }
    out = _replaceCommand(out, 'sqrt', (a) => '√(${a[0]})');
    for (final name in ['text', 'mathrm', 'mathbf', 'textbf', 'operatorname', 'mbox', 'vec', 'overline', 'hat', 'bar']) {
      out = _replaceCommand(out, name, (a) => a[0]);
    }
  }
  out = out
      .replaceAllMapped(RegExp(r'\^\{([^{}]*)\}|\^(\S)'), (m) {
        final value = m[1] ?? m[2]!;
        return toSuperscript(value) ?? '^($value)';
      })
      .replaceAllMapped(RegExp(r'_\{([^{}]*)\}|_(\S)'), (m) {
        final value = m[1] ?? m[2]!;
        return toSubscript(value) ?? '_($value)';
      })
      .replaceAll(RegExp(r'\\(left|right|displaystyle|,|;|!|:)'), '')
      .replaceAllMapped(RegExp(r'\\([a-zA-Z]+)'), (m) => _texSymbols[m[1]] ?? m[1]!)
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  return out.trim();
}

// ── LaTeX typed or pasted without $…$ around it ──────────────────────────────

/// Every way maths is marked: $$…$$, \[…\], \(…\), $…$ (hugging its content).
final mathPattern = RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?!\s)([^$\n\r]*?[^\s$])\$(?!\d)');

const _commands =
    'frac|dfrac|tfrac|sqrt|times|div|pm|mp|cdot|le|leq|ge|geq|ne|neq|approx|equiv|infty|alpha|beta|gamma|delta|Delta|theta|lambda|mu|pi|sigma|Sigma|omega|Omega|phi|rho|epsilon|varepsilon|int|sum|prod|lim|log|ln|sin|cos|tan|vec|hat|bar|overline|circ|degree|rightarrow|to|Rightarrow|leftrightarrow|rightleftharpoons|ce|mathrm|left|right|cdots|ldots|partial|nabla|angle|triangle|perp|parallel|propto|therefore|because|binom|overrightarrow|mathbf';

// x^2, x_1, H_{2}: a caret or underscore followed by a group, a digit/sign, or a single letter.
final _trigger = RegExp('\\\\(?:$_commands)(?![a-zA-Z])|[A-Za-z0-9)\\]}]\\s*[\\^_]\\s*(?:\\{|[0-9+-]|[A-Za-z](?![A-Za-z]))');
const _functionWords = {'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'log', 'ln', 'exp', 'lim', 'max', 'min'};
final _mathChar = RegExp(r"[A-Za-z0-9\s+\-*/=().,|<>'^_\[\]!:]");
final _space = RegExp(r'\s');
final _digit = RegExp(r'\d');

bool _isLetter(String ch) => _letter.hasMatch(ch);

/// Grows [start, end) over formula characters; stops at ordinary words.
(int, int) _growRun(String text, int start, int end) {
  int wordAt(int i) {
    // A plain word: two or more letters not belonging to a \command.
    final m = RegExp(r'^[A-Za-z]{2,}').firstMatch(text.substring(i));
    if (m == null) return 0;
    var k = i - 1;
    while (k >= 0 && _isLetter(text[k])) {
      k--;
    }
    if (k >= 0 && text[k] == r'\') return 0;
    return _functionWords.contains(m[0]) ? 0 : m[0]!.length;
  }

  // Left
  var left = start;
  while (left > 0) {
    final ch = text[left - 1];
    if (ch == '}') {
      var depth = 0;
      var k = left - 1;
      for (; k >= 0; k--) {
        if (text[k] == '}') {
          depth++;
        } else if (text[k] == '{') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (k < 0) break;
      left = k;
      continue;
    }
    if (!_mathChar.hasMatch(ch) && ch != r'\') break;
    if (_isLetter(ch)) {
      var k = left - 1;
      while (k > 0 && _isLetter(text[k - 1])) {
        k--;
      }
      if (k > 0 && text[k - 1] == r'\') {
        left = k - 1;
        continue;
      }
      if (left - k >= 2 && !_functionWords.contains(text.substring(k, left))) break;
      left = k;
      continue;
    }
    // Sentence punctuation ends the formula; a decimal point (3.5) does not.
    if ((ch == ':' || ch == ',' || ch == '.') && !(left < text.length && _digit.hasMatch(text[left]))) break;
    left--;
  }
  // Right
  var right = end;
  while (right < text.length) {
    final ch = text[right];
    if (ch == '{') {
      final close = _groupEnd(text, right);
      if (close < 0) break;
      right = close;
      continue;
    }
    if (ch == r'\') {
      final m = RegExp(r'^\\([a-zA-Z]+|.)').firstMatch(text.substring(right));
      right += m != null ? m[0]!.length : 1;
      continue;
    }
    if (!_mathChar.hasMatch(ch)) break;
    if (_isLetter(ch) && wordAt(right) > 0) break;
    if ((ch == ',' || ch == '.' || ch == ':') && (right + 1 >= text.length || _space.hasMatch(text[right + 1]))) break;
    right++;
  }
  // Leave surrounding spaces and sentence punctuation outside.
  while (left < right && _space.hasMatch(text[left])) {
    left++;
  }
  while (right > left && RegExp(r'[\s.,;:]').hasMatch(text[right - 1])) {
    right--;
  }
  return (left, right);
}

String _wrapPlainRun(String text) {
  if (!text.contains(r'\') && !text.contains('^') && !text.contains('_')) return text;
  final out = StringBuffer();
  var cursor = 0;
  var from = 0;
  while (from < text.length) {
    final match = _trigger.firstMatch(text.substring(from));
    if (match == null) break;
    final start = from + match.start;
    final end = from + match.end;
    from = end;
    if (start < cursor) continue;
    final (left, right) = _growRun(text, start, end);
    if (left < cursor || right <= left || RegExp(r'[\\^_]$').hasMatch(text.substring(left, right))) continue;
    out
      ..write(text.substring(cursor, left))
      ..write('\\(${text.substring(left, right)}\\)');
    cursor = right;
    from = right;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

/// Puts \( … \) around LaTeX that was pasted without delimiters ("x^2 + \frac{1}{2}").
String wrapBareLatex(String text) {
  if (text.isEmpty) return text;
  final out = StringBuffer();
  var cursor = 0;
  for (final match in mathPattern.allMatches(text)) {
    out
      ..write(_wrapPlainRun(text.substring(cursor, match.start)))
      ..write(match[0]);
    cursor = match.end;
  }
  out.write(_wrapPlainRun(text.substring(cursor)));
  return out.toString();
}

// ── MathML (Word, websites without a LaTeX copy) as LaTeX ────────────────────

const _mathmlFunctions = {..._functionWords, 'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh', 'det', 'gcd', 'deg'};

/// A MathML element as LaTeX.
String mathmlToTex(dom.Node? node) {
  if (node == null) return '';
  if (node is dom.Text) return node.text;
  if (node is! dom.Element) return '';
  final tag = (node.localName ?? '').replaceFirst('m:', '');
  final kids = node.children;
  String all() => node.nodes.map(mathmlToTex).join();
  String arg(int i) => i < kids.length ? mathmlToTex(kids[i]) : '';
  final text = node.text.trim();
  switch (tag) {
    case 'semantics':
      return kids.isEmpty ? '' : arg(0);
    case 'annotation':
    case 'annotation-xml':
      return '';
    case 'mi':
      if (_mathmlFunctions.contains(text)) return '\\$text ';
      if (text.length > 1) return '\\mathrm{$text}';
      return unicodeToTex(text);
    case 'mn':
      return text;
    case 'mo':
      return unicodeToTex(text);
    case 'mtext':
      return text.isEmpty ? '' : '\\text{$text}';
    case 'mspace':
      return r'\ ';
    case 'msup':
      return '{${arg(0)}}^{${arg(1)}}';
    case 'msub':
      return '{${arg(0)}}_{${arg(1)}}';
    case 'msubsup':
      return '{${arg(0)}}_{${arg(1)}}^{${arg(2)}}';
    case 'mfrac':
      return '\\frac{${arg(0)}}{${arg(1)}}';
    case 'msqrt':
      return '\\sqrt{${all()}}';
    case 'mroot':
      return '\\sqrt[${arg(1)}]{${arg(0)}}';
    case 'mover':
      final over = kids.length > 1 ? kids[1].text.trim() : '';
      if (over == '¯' || over == '‾' || over == '_') return '\\overline{${arg(0)}}';
      if (over == '→' || over == '\u20D7') return '\\vec{${arg(0)}}';
      if (over == '^' || over == 'ˆ') return '\\hat{${arg(0)}}';
      if (over == '˙' || over == '.') return '\\dot{${arg(0)}}';
      return '\\overset{${arg(1)}}{${arg(0)}}';
    case 'munder':
      return '\\underset{${arg(1)}}{${arg(0)}}';
    case 'munderover':
      return '{${arg(0)}}_{${arg(1)}}^{${arg(2)}}';
    case 'mfenced':
      final open = node.attributes['open'] ?? '(';
      final close = node.attributes['close'] ?? ')';
      return '\\left$open ${kids.map(mathmlToTex).join(', ')} \\right$close';
    case 'mtable':
      return '\\begin{matrix}${kids.map(mathmlToTex).join(r' \\ ')}\\end{matrix}';
    case 'mtr':
    case 'mlabeledtr':
      return kids.map(mathmlToTex).join(' & ');
    default:
      return all();
  }
}

// ── Copied HTML (websites, ChatGPT, Word, Google Docs) as question text ──────

const _blockTags = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'table', 'ul', 'ol', 'section', 'article', 'li'};

bool _hasAncestor(dom.Element element, bool Function(dom.Element) test) {
  var parent = element.parent;
  while (parent != null) {
    if (test(parent)) return true;
    parent = parent.parent;
  }
  return false;
}

bool _hasClass(dom.Element e, String name) => e.classes.contains(name);

dom.Element? _closest(dom.Element element, bool Function(dom.Element) test) {
  dom.Element? current = element;
  while (current != null) {
    if (test(current)) return current;
    current = current.parent;
  }
  return null;
}

String _wrapFormula(String latex, {required bool display}) => display ? '\$\$$latex\$\$' : '\\($latex\\)';

/// True when copied HTML has something plain text would lose: typeset maths
/// or raised/lowered text (H<sub>2</sub>O, x<sup>2</sup>, Google Docs spans).
bool hasRichScience(String html) =>
    RegExp(r'application/x-tex|<math[\s>]|<mjx-|<sup[\s>]|<sub[\s>]|vertical-align:\s*(super|sub)', caseSensitive: false).hasMatch(html);

/// Replaces typeset maths with its LaTeX, and raised/lowered text with x² / H₂O.
void _restoreScience(dom.Document doc) {
  // KaTeX, MathJax and Wikipedia keep the LaTeX source next to the drawing.
  for (final annotation in doc.querySelectorAll('annotation').toList()) {
    if (annotation.attributes['encoding'] != 'application/x-tex') continue;
    final latex = annotation.text.trim().replaceFirstMapped(RegExp(r'^\{\\displaystyle\s*([\s\S]*)\}$'), (m) => m[1]!).trim();
    final displayBlock = _closest(annotation, (e) => _hasClass(e, 'katex-display') || (e.localName == 'math' && e.attributes['display'] == 'block'));
    final target = displayBlock ??
        _closest(annotation, (e) => _hasClass(e, 'katex') || _hasClass(e, 'mwe-math-element') || e.localName == 'mjx-container') ??
        _closest(annotation, (e) => e.localName == 'math');
    if (target == null || target.parent == null) continue;
    target.replaceWith(dom.Text(_wrapFormula(latex, display: displayBlock != null)));
  }
  // MathJax 3 keeps a MathML copy for screen readers; Word and some sites paste bare MathML.
  for (final container in doc.querySelectorAll('mjx-container').toList()) {
    if (container.parent == null) continue;
    final math = container.querySelector('math');
    if (math == null) continue;
    final display = container.attributes['display'] == 'true' || math.attributes['display'] == 'block';
    container.replaceWith(dom.Text(_wrapFormula(mathmlToTex(math).trim(), display: display)));
  }
  for (final math in doc.querySelectorAll('math').toList()) {
    if (math.parent == null) continue;
    final latex = mathmlToTex(math).trim();
    if (latex.isEmpty) continue;
    math.replaceWith(dom.Text(_wrapFormula(latex, display: math.attributes['display'] == 'block')));
  }
  // The picture a site shows when it cannot typeset (its alt text is the LaTeX again).
  for (final image in doc.querySelectorAll('img').toList()) {
    if (image.classes.any((c) => c.startsWith('mwe-math-fallback'))) image.remove();
  }
  for (final el in doc.querySelectorAll('sup, sub, span').toList()) {
    if (el.parent == null) continue;
    final style = (el.attributes['style'] ?? '').replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final bool? superscript = el.localName == 'sup' || style.contains('vertical-align:super')
        ? true
        : el.localName == 'sub' || style.contains('vertical-align:sub')
            ? false
            : null;
    if (superscript == null) continue;
    if (_hasAncestor(el, (e) => e.localName == 'math' || _hasClass(e, 'katex') || e.localName == 'mjx-container')) continue;
    el.replaceWith(dom.Text(scriptText(el.text, superscript: superscript)));
  }
}

/// Copied HTML as plain question text: one line per paragraph, list numbers,
/// bold markers (**…**), LaTeX for every formula, and x² / H₂O kept.
String htmlToQuestionText(String html) {
  final doc = html_parser.parse(html);
  _restoreScience(doc);

  String walk(dom.Node node, int depth) {
    if (node is dom.Text) return node.text.replaceAll(RegExp(r'\s+'), ' ');
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    if (tag == 'br') return '\n';
    if (tag == 'hr') return '\n---\n';
    if (tag == 'style' || tag == 'script' || tag == 'button' || tag == 'head' || tag == 'title') return '';
    String children(dom.Node n, int d) => n.nodes.map((c) => walk(c, d)).join();

    if (tag == 'ol' || tag == 'ul') {
      var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      final lines = <String>[];
      for (final child in node.children) {
        if (child.localName != 'li') continue;
        var marker = '- ';
        if (tag == 'ol') {
          // Top-level numbers are questions; a numbered list inside one is its options.
          marker = depth == 0 ? '$number. ' : '${String.fromCharCode(64 + (number > 26 ? 26 : number))}) ';
          number++;
        }
        lines.add(marker + children(child, depth + 1).trim());
      }
      return '\n${lines.join('\n')}\n';
    }
    if (tag == 'tr') {
      return '${node.children.map((cell) => children(cell, depth).trim()).join(' | ')}\n';
    }
    final inner = children(node, depth);
    if ((tag == 'strong' || tag == 'b') && inner.trim().isNotEmpty) return '**${inner.trim()}**';
    return _blockTags.contains(tag) ? '\n$inner\n' : inner;
  }

  final body = doc.body ?? doc.documentElement;
  if (body == null) return '';
  return body.nodes
      .map((n) => walk(n, 0))
      .join()
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Plain text from the clipboard, tidied: Windows line ends, no-break and
/// zero-width spaces, and Word's private "Symbol font" characters.
String tidyPastedText(String text) {
  const symbolFont = {
    '\uF02D': '−', '\uF0B4': '×', '\uF0B8': '÷', '\uF0A3': '≤', '\uF0B3': '≥', '\uF0B9': '≠', '\uF0B1': '±',
    '\uF0A5': '∞', '\uF0AE': '→', '\uF0B0': '°', '\uF0D6': '√', '\uF070': 'π', '\uF071': 'θ', '\uF061': 'α',
    '\uF062': 'β', '\uF067': 'γ', '\uF064': 'δ', '\uF044': 'Δ', '\uF06C': 'λ', '\uF06D': 'μ', '\uF077': 'ω', '\uF057': 'Ω',
  };
  var out = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\u00a0', ' ').replaceAll(RegExp('[\u200b\u200c\u200d\ufeff]'), '');
  symbolFont.forEach((from, to) => out = out.replaceAll(from, to));
  return out;
}
