"""Lists tr('…') texts in lib/ that have no Bangla entry in lib/core/strings_bn.dart.

    python3 tool/missing_bangla.py            # every file
    python3 tool/missing_bangla.py lib/screens/student
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALL = re.compile(r"""(?<![\w.])tr\(\s*(['"])((?:\\.|(?!\1).)*)\1""", re.S)
KEY = re.compile(r"""^\s*(['"])((?:\\.|(?!\1).)*)\1\s*:""", re.M)


def unescape(text, quote):
    return text.replace("\\" + quote, quote).replace("\\\\", "\\")


def main(paths):
    bn = (ROOT / 'lib/core/strings_bn.dart').read_text(encoding='utf-8')
    known = {unescape(m.group(2), m.group(1)) for m in KEY.finditer(bn)}
    files = []
    for p in paths or ['lib']:
        path = ROOT / p
        files += [path] if path.is_file() else sorted(path.rglob('*.dart'))
    missing = {}
    for f in files:
        for m in CALL.finditer(f.read_text(encoding='utf-8')):
            text = unescape(m.group(2), m.group(1))
            if text.startswith('@') or text in known:
                continue
            missing.setdefault(text, f.relative_to(ROOT))
    for text, where in missing.items():
        print(f'{where}: {text!r}')
    print(f'{len(missing)} missing', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1:])
