#!/usr/bin/env python3
"""Apply mechanical Google-style fixes to Swift comments and Markdown prose.

Only comment text is ever rewritten. Code, string literals and backtick-quoted spans
are located first and masked, so a transform cannot reach an identifier, a `file.py:294`
citation, or a code sample. Run with --check to see what would change.
"""
import re, sys, argparse

# ---------------------------------------------------------------- comment extraction

def swift_comment_spans(text):
    """Yield (start, end) character ranges of comment *text* in a Swift source file.

    Tracks string literals so a `//` inside one is not mistaken for a comment, and
    handles both line and block comments.
    """
    spans, i, n = [], 0, len(text)
    in_str = in_multiline_str = False
    while i < n:
        c = text[i]
        if in_multiline_str:
            if text.startswith('"""', i):
                in_multiline_str = False; i += 3; continue
            i += 1; continue
        if in_str:
            if c == '\\': i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if text.startswith('"""', i):
            in_multiline_str = True; i += 3; continue
        if c == '"':
            in_str = True; i += 1; continue
        if text.startswith('//', i):
            j = i + 2
            while j < n and text[j] == '/': j += 1      # /// and //// markers
            e = text.find('\n', j)
            if e == -1: e = n
            spans.append((j, e)); i = e; continue
        if text.startswith('/*', i):
            e = text.find('*/', i + 2)
            e = n if e == -1 else e
            spans.append((i + 2, e)); i = e; continue
        i += 1
    return spans

def markdown_spans(text):
    """Whole file is prose, minus fenced code blocks and indented code."""
    spans, pos, fenced = [], 0, False
    for line in text.splitlines(keepends=True):
        s = line.lstrip()
        if s.startswith('```') or s.startswith('~~~'):
            fenced = not fenced; pos += len(line); continue
        if not fenced and not line.startswith('    ') and not line.startswith('\t'):
            spans.append((pos, pos + len(line)))
        pos += len(line)
    return spans

# ---------------------------------------------------------------- masking

MASK_PATTERNS = [
    r'`[^`\n]*`',                       # inline code / citations
    r'https?://\S+',                    # URLs
    r'\bhttps?:\S*',
    r'\b[\w./-]+\.(?:py|swift|md|c|h|go|json|ini|txt|yml):\d+',   # bare file:line
    r'\b0x[0-9A-Fa-f]+\b',              # hex constants
    r'"[^"\n]*"',                       # quoted literals: exact output/wire values
    r'\\u\{[0-9A-Fa-f]+\}',              # Unicode escapes
]
MASK_RE = re.compile('|'.join(MASK_PATTERNS))

def with_masked(fragment, fn):
    """Run `fn` over `fragment` with protected regions replaced by placeholders."""
    saved = []
    def stash(m):
        saved.append(m.group(0))
        return f'\x00{len(saved) - 1}\x00'
    masked = MASK_RE.sub(stash, fragment)
    out = fn(masked)
    return re.sub(r'\x00(\d+)\x00', lambda m: saved[int(m.group(1))], out)

# ---------------------------------------------------------------- transforms

CONTRACTIONS = {
    'are not': "aren't", 'cannot': "can't", 'could not': "couldn't",
    'did not': "didn't", 'do not': "don't", 'does not': "doesn't",
    'has not': "hasn't", 'have not': "haven't", 'how is': "how's",
    'is not': "isn't", 'it is': "it's", 'should not': "shouldn't",
    'they are': "they're", 'was not': "wasn't",
    'we are': "we're", 'we have': "we've", 'were not': "weren't",
    'what is': "what's", 'when is': "when's", 'where is': "where's",
    'will not': "won't",
}
LATIN = {r'\be\.g\.,?': 'for example,', r'\bi\.e\.,?': 'that is,', r'\betc\.': 'and so on'}

def apply_transforms(t, rules):
    if 'emdash' in rules:
        # Google.EmDash: '\s[—–]\s' — close the spaces around an em or en dash.
        t = re.sub(r'[ \t]+([—–])[ \t]+', r'\1', t)
    if 'spacing' in rules:
        # Google.Spacing: one space between sentences.
        t = re.sub(r'([a-z][.?!]) {2,}([A-Z])', r'\1 \2', t)
    if 'lyhyphens' in rules:
        t = re.sub(r'\b([^\s-]+ly)-(\w+)\b', r'\1 \2', t)
    if 'latin' in rules:
        for pat, rep in LATIN.items():
            t = re.sub(pat, rep, t, flags=re.I)
    if 'contractions' in rules:
        for a, b in CONTRACTIONS.items():
            def sub(m, b=b):
                w = m.group(0)
                return b[0].upper() + b[1:] if w[0].isupper() else b
            # A contraction is only legal when a complement follows: 'it is fine'
            # -> "it's fine", but 'how load-bearing it is.' must stay expanded.
            t = re.sub(r'\b' + a.replace(' ', r'\s+') + r'\b(?=\s+[\w`*"\'(\[])', sub, t, flags=re.I)
    if 'units' in rules:
        # Google.Units wants a space between number and unit. Time units read
        # better spelled out in prose; SI symbols stay abbreviated.
        WORDS = {'s': 'second', 'h': 'hour', 'min': 'minute', 'd': 'day'}
        def spell(m):
            n, u = m.group(1), m.group(2)
            w = WORDS[u]
            return f"{n} {w}" if n == '1' else f"{n} {w}s"
        t = re.sub(r'\b(\d+)(min|[shd])\b(?<!\b(?:19|20)\d\ds\b)', spell, t)
        t = re.sub(r'\b(\d+)(ns|ms|kB|MB|GB|TB)\b', r'\1 \2', t)
    if 'spelling' in rules:
        # Google.Spelling: American spelling.
        for a, b in {'unrecognised': 'unrecognized', 'recognised': 'recognized',
                     'recognise': 'recognize', 'resynchronise': 'resynchronize',
                     'harmonised': 'harmonized', 'colour': 'color',
                     'labour': 'labor', 'centre': 'center'}.items():
            def sub(m, b=b):
                w = m.group(0)
                return b[0].upper() + b[1:] if w[0].isupper() else b
            t = re.sub(r'\b' + a + r'\b', sub, t, flags=re.I)
    if 'wordlist' in rules:
        # Google.WordListCase / WordList: only the entries whose replacement is
        # unambiguous here. 'application', 'disable', 'abort', 'terminate' and
        # 'touch' name protocol fields or real API calls in this port and stay.
        for a, b in {r'\baka\b': 'also known as',
                     r'\bfunctionality\b': 'capability',
                     r'\bin order to\b': 'to',
                     r'\bregex\b': 'regular expression',
                     r'\bfile name\b': 'filename',
                     r'\bFile name\b': 'Filename',
                     r'\bfile path\b': 'filepath',
                     r'\bFile path\b': 'Filepath',
                     r'\bblock\(s\)': 'blocks',
                     r'\burl-safe\b': 'URL-safe'}.items():
            t = re.sub(a, b, t)
    if 'ordinal' in rules:
        for a, b in {'1st': 'first', '2nd': 'second', '3rd': 'third',
                     '4th': 'fourth', '5th': 'fifth'}.items():
            t = re.sub(r'\b' + a + r'\b', b, t)
    return t

SWIFT_CONT = r'(?://+[!<]?|\*)'

def fix_wrapped_dash(text, is_md, spans):
    """Google.EmDash also fires on ` —\n`: the newline counts as trailing space.

    A dash cannot close its right-hand gap across a line break, so pull the next
    line's first word up to meet it. The rendered comment then reads `word—word`.
    """
    def inside(p):
        return any(s <= p < e for s, e in spans)
    pat = (r'[ \t]*([—–])[ \t]*\n([ \t]*)(?![-*+>#]|\d+\.)(\S+)[ \t]*' if is_md
           else r'[ \t]*([—–])[ \t]*\n([ \t]*' + SWIFT_CONT + r'[ \t]*)(\S+)[ \t]*')
    def repl(m):
        word = m.group(3)
        if word.startswith('*/') or re.fullmatch(SWIFT_CONT, word):
            return m.group(0)
        if not (inside(m.start(1)) and inside(m.end(2))):
            return m.group(0)
        return m.group(1) + word + '\n' + m.group(2)
    out = pat and re.sub(pat, repl, text)
    if not is_md:   # a line left holding only its marker keeps no trailing space
        out = re.sub(r'^([ \t]*' + SWIFT_CONT + r')[ \t]+$', r'\1', out, flags=re.M)
    return out

def process(path, rules, check=False):
    text = original = open(path, encoding='utf-8').read()
    is_md = path.endswith('.md')
    spans = markdown_spans(text) if is_md else swift_comment_spans(text)
    if 'emdash' in rules:
        wrapped = fix_wrapped_dash(text, is_md, spans)
        if wrapped != text:
            text = wrapped
            spans = markdown_spans(text) if is_md else swift_comment_spans(text)
    out, last, changed = [], 0, (text != original)
    for s, e in spans:
        out.append(text[last:s])
        frag = text[s:e]
        new = with_masked(frag, lambda f: apply_transforms(f, rules))
        if new != frag: changed += 1
        out.append(new)
        last = e
    out.append(text[last:])
    result = ''.join(out)
    if result != original and not check:
        open(path, 'w', encoding='utf-8').write(result)
    return changed if result != original else 0

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--rules', default='emdash,spacing,lyhyphens,latin,contractions,units,ordinal')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    rules = set(a.rules.split(','))
    total = files = 0
    for f in a.files:
        c = process(f, rules, a.check)
        if c: files += 1; total += c
    print(f"{'would change' if a.check else 'changed'}: {files} files, {total} comment spans")
