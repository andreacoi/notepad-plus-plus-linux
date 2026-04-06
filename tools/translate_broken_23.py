#!/usr/bin/env python3
"""
Re-translate the 23 previously broken language files.
Fixed: strips ALL & accelerator markers, never re-inserts them.
macOS doesn't use Alt+letter menu accelerators, so & markers are pointless.
"""

import os
import re
import time
from googletrans import Translator

LOC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'resources', 'localization')

FILES_TO_FIX = {
    "amharic": "am", "armenian": "hy", "cebuano": "ceb", "chichewa": "ny",
    "ewe": "ee", "hausa": "ha", "hawaiian": "haw", "hmong": "hmn",
    "igbo": "ig", "javanese": "jw", "lao": "lo", "malagasy": "mg",
    "malayalam": "ml", "myanmar": "my", "odia": "or", "pashto": "ps",
    "sesotho": "st", "shona": "sn", "somali": "so", "sundanese": "su",
    "swahili": "sw", "xhosa": "xh", "yoruba": "yo",
}

translator = Translator()
api_calls = 0
DELAY = 1.2


def translate_text(text, dest):
    global api_calls
    if not text or not text.strip():
        return text
    try:
        time.sleep(DELAY)
        api_calls += 1
        r = translator.translate(text, dest=dest, src='en')
        return r.text
    except Exception as e:
        print(f"      ERR: {e}")
        time.sleep(3)
        return text


def translate_batch(texts, dest):
    global api_calls
    if not texts:
        return []
    if len(texts) == 1:
        return [translate_text(texts[0], dest)]

    combined = " ||| ".join(texts)
    if len(combined) > 4000:
        mid = len(texts) // 2
        return translate_batch(texts[:mid], dest) + translate_batch(texts[mid:], dest)

    try:
        time.sleep(DELAY)
        api_calls += 1
        r = translator.translate(combined, dest=dest, src='en')
        parts = [p.strip() for p in r.text.split("|||")]
        if len(parts) == len(texts):
            return parts
        parts2 = [p.strip() for p in r.text.split("|") if p.strip()]
        if len(parts2) == len(texts):
            return parts2
        print(f"      batch mismatch ({len(parts)} vs {len(texts)}), individual fallback")
        return [translate_text(t, dest) for t in texts]
    except Exception as e:
        print(f"      batch ERR: {e}")
        time.sleep(5)
        return texts


def xml_escape(s):
    s = s.replace('&', '&amp;')
    s = s.replace('"', '&quot;')
    s = s.replace('<', '&lt;')
    s = s.replace('>', '&gt;')
    return s


def xml_unescape(s):
    s = s.replace('&amp;', '&')
    s = s.replace('&quot;', '"')
    s = s.replace('&lt;', '<')
    s = s.replace('&gt;', '>')
    return s


def strip_accelerators(s):
    """Remove & accelerator markers completely. macOS doesn't use them."""
    return s.replace('&', '')


def translate_file(content, dest_code):
    """Translate ALL translatable attributes. No & reinsertion."""
    translatable_attrs = [
        'name', 'title', 'message', 'value',
        'titleFind', 'titleReplace', 'titleFindInFiles', 'titleFindInProjects', 'titleMark',
        'alternativeName',
    ]

    attr_pattern = re.compile(
        r'(' + '|'.join(translatable_attrs) + r')="([^"]*)"'
    )

    matches = list(attr_pattern.finditer(content))

    # Filter to translatable strings only
    translatable = []
    for m in matches:
        attr_name = m.group(1)
        value = m.group(2)
        unescaped = xml_unescape(value)
        clean = strip_accelerators(unescaped)

        # Skip empty, numeric, technical
        if not clean.strip():
            continue
        if re.match(r'^\d+$', clean.strip()):
            continue
        if clean.startswith('$') or clean.startswith('@'):
            continue
        if attr_name == 'name' and clean.endswith('.xml'):
            continue

        translatable.append((m, attr_name, value, clean))

    if not translatable:
        return content, 0

    texts = [t[3] for t in translatable]

    # Batch translate
    all_translations = []
    batch_size = 20
    total = len(texts)
    for i in range(0, total, batch_size):
        batch = texts[i:i + batch_size]
        translated = translate_batch(batch, dest_code)
        all_translations.extend(translated)
        pct = min(100, int((i + len(batch)) / total * 100))
        print(f"\r      Progress: {pct}% ({i + len(batch)}/{total})", end="", flush=True)
    print()

    # Replace from end to start (preserves positions)
    result = content
    for (m, attr_name, old_value, _), new_text in reversed(list(zip(translatable, all_translations))):
        # XML-escape the translated text. No & accelerators added back.
        escaped = xml_escape(new_text)
        old_attr = f'{attr_name}="{old_value}"'
        new_attr = f'{attr_name}="{escaped}"'
        result = result[:m.start()] + new_attr + result[m.end():]

    count = len(translatable)
    return result, count


def main():
    print(f"Re-translating {len(FILES_TO_FIX)} broken files (no & markers)\n")

    global api_calls
    start = time.time()
    total = 0
    idx = 0

    for stem, code in sorted(FILES_TO_FIX.items()):
        idx += 1
        path = os.path.join(LOC_DIR, f'{stem}.xml')
        if not os.path.exists(path):
            print(f"  [{idx}] {stem}.xml NOT FOUND")
            continue

        print(f"  [{idx}] {stem}.xml ({code})...")

        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        new_content, count = translate_file(content, code)

        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_content)

        total += count
        print(f"      {count} strings translated")

    elapsed = time.time() - start
    print(f"\nDone! {total} strings, {api_calls} API calls, {elapsed/60:.1f} minutes")


if __name__ == '__main__':
    main()
