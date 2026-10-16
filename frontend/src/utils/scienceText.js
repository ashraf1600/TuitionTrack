/**
 * Science and maths text that arrives from other places (ChatGPT, Word,
 * Google Docs, websites, PDFs) made to show the way it looked there.
 *
 * The same rules live in the app (mobile/lib/core/science_text.dart);
 * keep the two in step.
 */

const SUPERSCRIPTS = {
  0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹',
  '+': '⁺', '-': '⁻', '−': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', n: 'ⁿ', i: 'ⁱ',
};
const SUBSCRIPTS = {
  0: '₀', 1: '₁', 2: '₂', 3: '₃', 4: '₄', 5: '₅', 6: '₆', 7: '₇', 8: '₈', 9: '₉',
  '+': '₊', '-': '₋', '−': '₋', '=': '₌', '(': '₍', ')': '₎',
  a: 'ₐ', e: 'ₑ', o: 'ₒ', x: 'ₓ', h: 'ₕ', k: 'ₖ', l: 'ₗ', m: 'ₘ', n: 'ₙ', p: 'ₚ', s: 'ₛ', t: 'ₜ',
};
const FROM_SUPERSCRIPT = Object.fromEntries(Object.entries(SUPERSCRIPTS).filter(([k]) => k !== '−').map(([k, v]) => [v, k]));
const FROM_SUBSCRIPT = Object.fromEntries(Object.entries(SUBSCRIPTS).filter(([k]) => k !== '−').map(([k, v]) => [v, k]));

const mapAll = (text, table) => {
  let out = '';
  for (const ch of text) {
    if (!(ch in table)) return null;
    out += table[ch];
  }
  return out;
};

/** "2" -> "²", "-3" -> "⁻³"; null when a character has no superscript form. */
export const toSuperscript = (text) => (text.trim() ? mapAll(text.trim(), SUPERSCRIPTS) : null);
/** "2" -> "₂"; null when a character has no subscript form. */
export const toSubscript = (text) => (text.trim() ? mapAll(text.trim(), SUBSCRIPTS) : null);

/** Text that was raised (<sup>) or lowered (<sub>) in the source, kept readable as plain text. */
export function scriptText(text, kind) {
  const clean = text.replace(/\s+/g, ' ').trim();
  if (!clean) return '';
  const unicode = kind === 'sup' ? toSuperscript(clean) : toSubscript(clean);
  if (unicode) return unicode;
  return kind === 'sup' ? `\\({}^{\\text{${clean}}}\\)` : `\\({}_{\\text{${clean}}}\\)`;
}

// Unicode symbols as LaTeX commands, for inside formulas.
const UNICODE_TEX = {
  '−': '-', '–': '-', '×': '\\times ', '÷': '\\div ', '·': '\\cdot ', '⋅': '\\cdot ', '∙': '\\cdot ',
  '≤': '\\le ', '≥': '\\ge ', '≠': '\\neq ', '±': '\\pm ', '∓': '\\mp ', '≈': '\\approx ', '≡': '\\equiv ',
  '∼': '\\sim ', '≅': '\\cong ', '∝': '\\propto ', '∞': '\\infty ', '→': '\\rightarrow ', '←': '\\leftarrow ',
  '↔': '\\leftrightarrow ', '⇌': '\\rightleftharpoons ', '⇒': '\\Rightarrow ', '⇔': '\\Leftrightarrow ',
  '↑': '\\uparrow ', '↓': '\\downarrow ', '°': '^\\circ ', '∠': '\\angle ', '△': '\\triangle ',
  '∴': '\\therefore ', '∵': '\\because ', '∑': '\\sum ', '∏': '\\prod ', '∫': '\\int ', '∮': '\\oint ',
  '∂': '\\partial ', '∇': '\\nabla ', '∈': '\\in ', '∉': '\\notin ', '⊂': '\\subset ', '⊆': '\\subseteq ',
  '∪': '\\cup ', '∩': '\\cap ', '∅': '\\emptyset ', '∀': '\\forall ', '∃': '\\exists ', '∥': '\\parallel ',
  '⊥': '\\perp ', '′': "'", '″': "''", '…': '\\ldots ', '⋯': '\\cdots ', 'ℏ': '\\hbar ', 'Å': '\\text{Å}',
  'α': '\\alpha ', 'β': '\\beta ', 'γ': '\\gamma ', 'δ': '\\delta ', 'ε': '\\varepsilon ', 'ϵ': '\\epsilon ',
  'ζ': '\\zeta ', 'η': '\\eta ', 'θ': '\\theta ', 'ϑ': '\\vartheta ', 'ι': '\\iota ', 'κ': '\\kappa ',
  'λ': '\\lambda ', 'μ': '\\mu ', 'µ': '\\mu ', 'ν': '\\nu ', 'ξ': '\\xi ', 'π': '\\pi ', 'ρ': '\\rho ',
  'σ': '\\sigma ', 'τ': '\\tau ', 'υ': '\\upsilon ', 'φ': '\\phi ', 'ϕ': '\\phi ', 'χ': '\\chi ', 'ψ': '\\psi ',
  'ω': '\\omega ', 'Γ': '\\Gamma ', 'Δ': '\\Delta ', '∆': '\\Delta ', 'Θ': '\\Theta ', 'Λ': '\\Lambda ',
  'Ξ': '\\Xi ', 'Π': '\\Pi ', 'Σ': '\\Sigma ', 'Υ': '\\Upsilon ', 'Φ': '\\Phi ', 'Ψ': '\\Psi ', 'Ω': '\\Omega ',
  '\u2126': '\\Omega ', '½': '\\frac{1}{2}', '⅓': '\\frac{1}{3}', '⅔': '\\frac{2}{3}', '¼': '\\frac{1}{4}', '¾': '\\frac{3}{4}',
  '\u00a0': ' ', '\u200b': '',
};
const TEXT_COMMANDS = new Set(['text', 'textrm', 'textbf', 'textit', 'mbox', 'mathrm', 'operatorname']);

/** Index just past the group that starts at `start` ("{…}" with nesting), or -1. */
function groupEnd(source, start) {
  if (source[start] !== '{') return -1;
  let depth = 0;
  for (let i = start; i < source.length; i += 1) {
    if (source[i] === '\\') {
      i += 1;
    } else if (source[i] === '{') {
      depth += 1;
    } else if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  return -1;
}

/** Unicode maths symbols inside a formula as LaTeX commands (text groups are left alone). */
export function unicodeToTex(tex) {
  let out = '';
  for (let i = 0; i < tex.length; ) {
    const ch = tex[i];
    if (ch === '\\') {
      const name = /^\\([a-zA-Z]+)/.exec(tex.slice(i));
      if (name && TEXT_COMMANDS.has(name[1])) {
        let j = i + name[0].length;
        while (tex[j] === ' ') j += 1;
        const end = groupEnd(tex, j);
        if (end > 0) {
          out += tex.slice(i, end);
          i = end;
          continue;
        }
      }
      out += tex.slice(i, i + (name ? name[0].length : 2));
      i += name ? name[0].length : 2;
      continue;
    }
    // A run of superscript or subscript characters: x² -> x^{2}.
    if (ch in FROM_SUPERSCRIPT || ch in FROM_SUBSCRIPT) {
      const table = ch in FROM_SUPERSCRIPT ? FROM_SUPERSCRIPT : FROM_SUBSCRIPT;
      let run = '';
      while (i < tex.length && tex[i] in table) {
        run += table[tex[i]];
        i += 1;
      }
      out += `${table === FROM_SUPERSCRIPT ? '^' : '_'}{${run}}`;
      continue;
    }
    if (ch === '√') {
      // √2, √x, √(b²−4ac) -> \sqrt{…}
      let j = i + 1;
      while (tex[j] === ' ') j += 1;
      let radicand = '';
      if (tex[j] === '(' || tex[j] === '{') {
        const close = tex[j] === '(' ? ')' : '}';
        let depth = 0;
        let k = j;
        for (; k < tex.length; k += 1) {
          if (tex[k] === tex[j]) depth += 1;
          else if (tex[k] === close && (depth -= 1) === 0) break;
        }
        if (k < tex.length) {
          radicand = tex.slice(j + 1, k);
          j = k + 1;
        }
      } else {
        const run = /^[A-Za-z0-9.]+/.exec(tex.slice(j));
        if (run) {
          radicand = run[0];
          j += run[0].length;
        }
      }
      out += radicand ? `\\sqrt{${unicodeToTex(radicand)}}` : '\\sqrt{}';
      i = j;
      continue;
    }
    out += UNICODE_TEX[ch] ?? ch;
    i += 1;
  }
  return out;
}

// ── Chemistry: \ce{…} (mhchem) for renderers that do not have it ─────────────

const CE_STATES = new Set(['s', 'l', 'g', 'aq']);

function ceSpecies(token) {
  if (token === '+') return '+';
  let out = '';
  let i = 0;
  const coefficient = /^(\d+(?:\/\d+)?|\d*\.\d+)(?=[A-Z([])/.exec(token);
  if (coefficient) {
    out += `${coefficient[1]}\\,`;
    i = coefficient[1].length;
  }
  let body = '';
  while (i < token.length) {
    const rest = token.slice(i);
    let m;
    if ((m = /^\^\{([^}]*)\}/.exec(rest)) || (m = /^\^(\d*[+-]|\d+)/.exec(rest))) {
      body += `^{${m[1]}}`;
    } else if ((m = /^(\d*[+-])$/.exec(rest)) && body) {
      // A charge at the end without a caret: Cu2+, Cl-
      body += `^{${m[1]}}`;
    } else if ((m = /^\((s|l|g|aq)\)/.exec(rest)) && CE_STATES.has(m[1])) {
      body += `\\,\\mathrm{(${m[1]})}`;
    } else if ((m = /^\d+/.exec(rest))) {
      body += `_{${m[0]}}`;
    } else if ((m = /^[A-Z][a-z]*/.exec(rest))) {
      body += `\\mathrm{${m[0]}}`;
    } else if ((m = /^[.*·]/.exec(rest))) {
      body += '\\cdot ';
    } else {
      m = [rest[0]];
      body += rest[0];
    }
    i += m[0].length;
  }
  return out + body;
}

/** "2H2 + O2 -> 2H2O" (mhchem) as plain LaTeX. */
export function ceToTex(formula) {
  const arrows = [
    [/<=>|<-->|⇌/g, ' \\rightleftharpoons '],
    [/<->|↔/g, ' \\leftrightarrow '],
    [/->|→/g, ' \\rightarrow '],
    [/<-|←/g, ' \\leftarrow '],
  ];
  let text = formula.trim();
  // An arrow with something written over it: ->[\Delta]
  text = text.replace(/->\[([^\]]*)\]/g, (_, over) => ` \\xrightarrow{${over}} `);
  for (const [pattern, tex] of arrows) text = text.replace(pattern, tex);
  return text
    .split(/\s+/)
    .filter(Boolean)
    .map((token) => {
      if (token.startsWith('\\')) return token;
      if (token === '^') return '\\uparrow';
      if (token === 'v') return '\\downarrow';
      return ceSpecies(token);
    })
    .join(' ');
}

/** Replace \cmd{…} (balanced) everywhere with `convert(argument)`. */
function replaceCommand(tex, name, convert, args = 1) {
  const pattern = new RegExp(`\\\\${name}(?![a-zA-Z])\\s*`, 'g');
  let out = '';
  let cursor = 0;
  let match;
  while ((match = pattern.exec(tex))) {
    const values = [];
    let j = match.index + match[0].length;
    for (let a = 0; a < args; a += 1) {
      while (tex[j] === ' ') j += 1;
      const end = groupEnd(tex, j);
      if (end < 0) break;
      values.push(tex.slice(j + 1, end - 1));
      j = end;
    }
    if (values.length < args) continue;
    out += tex.slice(cursor, match.index) + convert(...values);
    cursor = j;
    pattern.lastIndex = j;
  }
  return out + tex.slice(cursor);
}

/**
 * A formula copied from ChatGPT, Overleaf or a textbook, cleaned up so the
 * renderer understands it: chemistry (\ce, \pu), units (\si, \SI, \qty),
 * numbered environments, labels, and Unicode symbols.
 */
export function prepareTex(tex, { keepCe = false } = {}) {
  let out = tex
    .replace(/\\label\{[^}]*\}|\\tag\*?\{[^}]*\}|\\nonumber|\\notag/g, '')
    .replace(/\\begin\{(align|eqnarray)\*?\}/g, '\\begin{aligned}')
    .replace(/\\end\{(align|eqnarray)\*?\}/g, '\\end{aligned}')
    .replace(/\\begin\{gather\*?\}/g, '\\begin{gathered}')
    .replace(/\\end\{gather\*?\}/g, '\\end{gathered}')
    .replace(/\\(?:begin|end)\{(?:equation|displaymath|math)\*?\}/g, '')
    .replace(/\\lt(?![a-zA-Z])/g, '<')
    .replace(/\\gt(?![a-zA-Z])/g, '>')
    .replace(/\\celsius(?![a-zA-Z])/g, '^\\circ\\mathrm{C}');
  if (!keepCe) {
    out = replaceCommand(out, 'ce', (body) => ceToTex(body));
  }
  out = replaceCommand(out, 'pu', (body) => `\\mathrm{${body}}`);
  out = replaceCommand(out, 'SI', (value, unit) => `${value}\\,\\mathrm{${unit}}`, 2);
  out = replaceCommand(out, 'qty', (value, unit) => `${value}\\,\\mathrm{${unit}}`, 2);
  out = replaceCommand(out, 'si', (unit) => `\\mathrm{${unit}}`);
  out = replaceCommand(out, 'unit', (unit) => `\\mathrm{${unit}}`);
  out = replaceCommand(out, 'textsuperscript', (body) => `^{\\text{${body}}}`);
  out = replaceCommand(out, 'textsubscript', (body) => `_{\\text{${body}}}`);
  return unicodeToTex(out).trim();
}

// ── A formula as readable plain text (when it cannot be typeset) ─────────────

const TEX_SYMBOLS = Object.fromEntries(
  Object.entries(UNICODE_TEX)
    .filter(([, tex]) => /^\\[a-zA-Z]+ $/.test(tex))
    .map(([symbol, tex]) => [tex.trim().slice(1), symbol])
);
Object.assign(TEX_SYMBOLS, { le: '≤', leq: '≤', ge: '≥', geq: '≥', ne: '≠', to: '→', circ: '°', degree: '°', epsilon: 'ε', cdots: '⋯', ldots: '…', quad: ' ', qquad: '  ' });

/** "x^{2}+\frac{1}{2}" -> "x²+(1)/(2)": readable when the formula cannot be typeset. */
export function texToPlain(tex) {
  let out = prepareTex(tex);
  for (let pass = 0; pass < 4; pass += 1) {
    out = replaceCommand(out, 'frac', (a, b) => `(${a})/(${b})`, 2);
    out = replaceCommand(out, 'dfrac', (a, b) => `(${a})/(${b})`, 2);
    out = replaceCommand(out, 'tfrac', (a, b) => `(${a})/(${b})`, 2);
    out = replaceCommand(out, 'sqrt', (a) => `√(${a})`);
    for (const name of ['text', 'mathrm', 'mathbf', 'textbf', 'operatorname', 'mbox', 'vec', 'overline', 'hat', 'bar']) {
      out = replaceCommand(out, name, (a) => a);
    }
  }
  out = out
    .replace(/\^\{([^{}]*)\}|\^(\S)/g, (_, group, single) => {
      const value = group ?? single;
      return toSuperscript(value) ?? `^(${value})`;
    })
    .replace(/_\{([^{}]*)\}|_(\S)/g, (_, group, single) => {
      const value = group ?? single;
      return toSubscript(value) ?? `_(${value})`;
    })
    .replace(/\\(left|right|displaystyle|,|;|!|:)/g, '')
    .replace(/\\([a-zA-Z]+)/g, (whole, name) => TEX_SYMBOLS[name] ?? name)
    .replace(/[{}]/g, '')
    .replace(/\s+/g, ' ');
  return out.trim();
}

// ── LaTeX typed or pasted without $…$ around it ──────────────────────────────

const MATH_PATTERN = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?!\s)([^$\n\r]*?[^\s$])\$(?!\d)/g;
const COMMANDS = 'frac|dfrac|tfrac|sqrt|times|div|pm|mp|cdot|le|leq|ge|geq|ne|neq|approx|equiv|infty|alpha|beta|gamma|delta|Delta|theta|lambda|mu|pi|sigma|Sigma|omega|Omega|phi|rho|epsilon|varepsilon|int|sum|prod|lim|log|ln|sin|cos|tan|vec|hat|bar|overline|circ|degree|rightarrow|to|Rightarrow|leftrightarrow|rightleftharpoons|ce|mathrm|left|right|cdots|ldots|partial|nabla|angle|triangle|perp|parallel|propto|therefore|because|binom|overrightarrow|mathbf';
// x^2, x_1, H_{2}: a caret or underscore followed by a group, a digit/sign, or a single letter.
const TRIGGER = new RegExp(`\\\\(?:${COMMANDS})(?![a-zA-Z])|[A-Za-z0-9)\\]}]\\s*[\\^_]\\s*(?:\\{|[0-9+-]|[A-Za-z](?![A-Za-z]))`, 'g');
const FUNCTION_WORDS = new Set(['sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'log', 'ln', 'exp', 'lim', 'max', 'min']);
const MATH_CHAR = /[A-Za-z0-9\s+\-*/=().,|<>'^_[\]!:]/;

/** Grows [start, end) over formula characters; stops at ordinary words. */
function growRun(text, start, end) {
  const isWordAt = (i) => {
    // A plain word: two or more letters not belonging to a \command.
    const m = /^[A-Za-z]{2,}/.exec(text.slice(i));
    if (!m) return 0;
    let k = i - 1;
    while (k >= 0 && /[A-Za-z]/.test(text[k])) k -= 1;
    if (k >= 0 && text[k] === '\\') return 0;
    return FUNCTION_WORDS.has(m[0]) ? 0 : m[0].length;
  };
  // Left
  let left = start;
  while (left > 0) {
    const ch = text[left - 1];
    if (ch === '}') {
      let depth = 0;
      let k = left - 1;
      for (; k >= 0; k -= 1) {
        if (text[k] === '}') depth += 1;
        else if (text[k] === '{' && (depth -= 1) === 0) break;
      }
      if (k < 0) break;
      left = k;
      continue;
    }
    if (!MATH_CHAR.test(ch) && ch !== '\\') break;
    if (/[A-Za-z]/.test(ch)) {
      let k = left - 1;
      while (k > 0 && /[A-Za-z]/.test(text[k - 1])) k -= 1;
      if (k > 0 && text[k - 1] === '\\') {
        left = k - 1;
        continue;
      }
      if (left - k >= 2 && !FUNCTION_WORDS.has(text.slice(k, left))) break;
      left = k;
      continue;
    }
    // Sentence punctuation ends the formula; a decimal point (3.5) does not.
    if ((ch === ':' || ch === ',' || ch === '.') && !/\d/.test(text[left] ?? '')) break;
    left -= 1;
  }
  // Right
  let right = end;
  while (right < text.length) {
    const ch = text[right];
    if (ch === '{') {
      const close = groupEnd(text, right);
      if (close < 0) break;
      right = close;
      continue;
    }
    if (ch === '\\') {
      const m = /^\\([a-zA-Z]+|.)/.exec(text.slice(right));
      right += m ? m[0].length : 1;
      continue;
    }
    if (!MATH_CHAR.test(ch)) break;
    if (/[A-Za-z]/.test(ch) && isWordAt(right)) break;
    if ((ch === ',' || ch === '.' || ch === ':') && (right + 1 >= text.length || /\s/.test(text[right + 1]))) break;
    right += 1;
  }
  // Leave surrounding spaces and sentence punctuation outside.
  while (left < right && /\s/.test(text[left])) left += 1;
  while (right > left && /[\s.,;:]/.test(text[right - 1])) right -= 1;
  return [left, right];
}

function wrapPlainRun(text) {
  if (!text.includes('\\') && !/[\^_]/.test(text)) return text;
  let out = '';
  let cursor = 0;
  TRIGGER.lastIndex = 0;
  let match;
  while ((match = TRIGGER.exec(text))) {
    if (match.index < cursor) continue;
    const [left, right] = growRun(text, match.index, match.index + match[0].length);
    if (left < cursor || right <= left || /[\\^_]$/.test(text.slice(left, right))) continue;
    out += `${text.slice(cursor, left)}\\(${text.slice(left, right)}\\)`;
    cursor = right;
    TRIGGER.lastIndex = right;
  }
  return out + text.slice(cursor);
}

/** Puts \( … \) around LaTeX that was pasted without delimiters ("x^2 + \frac{1}{2}"). */
export function wrapBareLatex(text) {
  if (!text) return text;
  let out = '';
  let cursor = 0;
  for (const match of text.matchAll(MATH_PATTERN)) {
    out += wrapPlainRun(text.slice(cursor, match.index)) + match[0];
    cursor = match.index + match[0].length;
  }
  return out + wrapPlainRun(text.slice(cursor));
}

// ── MathML (Word, websites without a LaTeX copy) as LaTeX ────────────────────

const MATHML_FUNCTIONS = new Set([...FUNCTION_WORDS, 'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh', 'det', 'gcd', 'deg']);

/** A <math> element (or any MathML node) as LaTeX. */
export function mathmlToTex(node) {
  if (!node) return '';
  if (node.nodeType === 3) return node.textContent;
  if (node.nodeType !== 1) return '';
  const tag = node.localName.replace(/^m:/, '');
  const kids = [...node.children];
  const all = () => [...node.childNodes].map(mathmlToTex).join('');
  const arg = (i) => mathmlToTex(kids[i]);
  const text = () => node.textContent.trim();
  switch (tag) {
    case 'semantics':
      return kids.length ? arg(0) : '';
    case 'annotation':
    case 'annotation-xml':
      return '';
    case 'mi': {
      const t = text();
      if (MATHML_FUNCTIONS.has(t)) return `\\${t} `;
      if (t.length > 1) return `\\mathrm{${t}}`;
      return unicodeToTex(t);
    }
    case 'mn':
      return text();
    case 'mo':
      return unicodeToTex(text());
    case 'mtext':
      return text() ? `\\text{${text()}}` : '';
    case 'mspace':
      return '\\ ';
    case 'msup':
      return `{${arg(0)}}^{${arg(1)}}`;
    case 'msub':
      return `{${arg(0)}}_{${arg(1)}}`;
    case 'msubsup':
      return `{${arg(0)}}_{${arg(1)}}^{${arg(2)}}`;
    case 'mfrac':
      return `\\frac{${arg(0)}}{${arg(1)}}`;
    case 'msqrt':
      return `\\sqrt{${all()}}`;
    case 'mroot':
      return `\\sqrt[${arg(1)}]{${arg(0)}}`;
    case 'mover': {
      const over = kids[1]?.textContent.trim();
      if (over === '¯' || over === '‾' || over === '_') return `\\overline{${arg(0)}}`;
      if (over === '→' || over === '⃗') return `\\vec{${arg(0)}}`;
      if (over === '^' || over === 'ˆ') return `\\hat{${arg(0)}}`;
      if (over === '˙' || over === '.') return `\\dot{${arg(0)}}`;
      return `\\overset{${arg(1)}}{${arg(0)}}`;
    }
    case 'munder':
      return `\\underset{${arg(1)}}{${arg(0)}}`;
    case 'munderover':
      return `{${arg(0)}}_{${arg(1)}}^{${arg(2)}}`;
    case 'mfenced': {
      const open = node.getAttribute('open') ?? '(';
      const close = node.getAttribute('close') ?? ')';
      return `\\left${open} ${kids.map(mathmlToTex).join(', ')} \\right${close}`;
    }
    case 'mtable':
      return `\\begin{matrix}${kids.map(mathmlToTex).join(' \\\\ ')}\\end{matrix}`;
    case 'mtr':
    case 'mlabeledtr':
      return kids.map(mathmlToTex).join(' & ');
    default:
      return all();
  }
}
