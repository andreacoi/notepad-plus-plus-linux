#!/usr/bin/env python3
"""
Translate Notepad++ localization XML files using Google Translate.
Uses regex replacement to preserve original XML formatting (no ElementTree rewriting).

- Existing 94 languages: translate only <MacStrings> entries
- New 43 languages: translate ALL translatable text attributes
"""

import os
import sys
import re
import time
from googletrans import Translator

LOC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'resources', 'localization')

LANG_CODES = {
    "afrikaans": "af", "albanian": "sq", "arabic": "ar", "azerbaijani": "az",
    "basque": "eu", "belarusian": "be", "bengali": "bn", "bosnian": "bs",
    "brazilian_portuguese": "pt", "bulgarian": "bg", "catalan": "ca",
    "chineseSimplified": "zh-cn", "corsican": "co", "croatian": "hr",
    "czech": "cs", "danish": "da", "dutch": "nl", "esperanto": "eo",
    "estonian": "et", "farsi": "fa", "finnish": "fi", "french": "fr",
    "galician": "gl", "georgian": "ka", "german": "de", "greek": "el",
    "gujarati": "gu", "hebrew": "iw", "hindi": "hi", "hongKongCantonese": "zh-tw",
    "hungarian": "hu", "indonesian": "id", "irish": "ga", "italian": "it",
    "japanese": "ja", "kannada": "kn", "kazakh": "kk", "korean": "ko",
    "kurdish": "ku", "kyrgyz": "ky", "latvian": "lv", "lithuanian": "lt",
    "luxembourgish": "lb", "macedonian": "mk", "malay": "ms", "marathi": "mr",
    "mongolian": "mn", "nepali": "ne", "norwegian": "no", "nynorsk": "no",
    "polish": "pl", "portuguese": "pt", "punjabi": "pa", "romanian": "ro",
    "russian": "ru", "serbian": "sr", "serbianCyrillic": "sr", "sinhala": "si",
    "slovak": "sk", "slovenian": "sl", "spanish": "es", "spanish_ar": "es",
    "swedish": "sv", "tagalog": "tl", "taiwaneseMandarin": "zh-tw",
    "tajikCyrillic": "tg", "tamil": "ta", "telugu": "te", "thai": "th",
    "turkish": "tr", "ukrainian": "uk", "urdu": "ur", "uyghur": "ug",
    "uzbek": "uz", "uzbekCyrillic": "uz", "vietnamese": "vi", "welsh": "cy",
    "zulu": "zu",
    # New 43
    "amharic": "am", "armenian": "hy", "aymara": "ay", "bambara": "bm",
    "bhojpuri": "bho", "cebuano": "ceb", "chichewa": "ny", "dhivehi": "dv",
    "dogri": "doi", "ewe": "ee", "guarani": "gn", "hausa": "ha",
    "hawaiian": "haw", "hmong": "hmn", "igbo": "ig", "ilocano": "ilo",
    "javanese": "jw", "kinyarwanda": "rw", "konkani": "gom", "krio": "kri",
    "lao": "lo", "lingala": "ln", "maithili": "mai", "malagasy": "mg",
    "malayalam": "ml", "mizo": "lus", "myanmar": "my", "odia": "or",
    "pashto": "ps", "quechua": "qu", "sepedi": "nso", "sesotho": "st",
    "shona": "sn", "somali": "so", "sundanese": "su", "swahili": "sw",
    "tigrinya": "ti", "tsonga": "ts", "turkmen": "tk", "twi": "ak",
    "xhosa": "xh", "yoruba": "yo",
}

NEW_LANGS = {
    "amharic", "armenian", "assamese", "aymara", "bambara", "bhojpuri",
    "cebuano", "chichewa", "dhivehi", "dogri", "ewe", "guarani", "hausa",
    "hawaiian", "hmong", "igbo", "ilocano", "javanese", "kinyarwanda",
    "konkani", "krio", "lao", "lingala", "maithili", "malagasy", "malayalam",
    "mizo", "myanmar", "odia", "pashto", "quechua", "sepedi", "sesotho",
    "shona", "somali", "sundanese", "swahili", "tigrinya", "tsonga",
    "turkmen", "twi", "xhosa", "yoruba",
}

translator = Translator()
api_calls = 0
DELAY = 1.2


def translate_text(text, dest):
    """Translate a single string. Returns original on failure."""
    global api_calls
    if not text or not text.strip():
        return text
    try:
        time.sleep(DELAY)
        api_calls += 1
        result = translator.translate(text, dest=dest, src='en')
        return result.text
    except Exception as e:
        print(f"      ERR: {e}")
        time.sleep(3)
        return text


def translate_batch(texts, dest):
    """Translate a batch using ||| delimiter. Falls back to individual on mismatch."""
    global api_calls
    if not texts:
        return []
    if len(texts) == 1:
        return [translate_text(texts[0], dest)]

    delimiter = " ||| "
    combined = delimiter.join(texts)

    # Split into smaller chunks if too long
    if len(combined) > 4000:
        mid = len(texts) // 2
        return translate_batch(texts[:mid], dest) + translate_batch(texts[mid:], dest)

    try:
        time.sleep(DELAY)
        api_calls += 1
        result = translator.translate(combined, dest=dest, src='en')
        parts = [p.strip() for p in result.text.split("|||")]

        if len(parts) == len(texts):
            return parts

        # Try splitting by |
        parts2 = [p.strip() for p in result.text.split("|") if p.strip()]
        if len(parts2) == len(texts):
            return parts2

        # Fall back to individual translations
        print(f"      batch mismatch ({len(parts)} vs {len(texts)}), translating individually")
        return [translate_text(t, dest) for t in texts]
    except Exception as e:
        print(f"      batch ERR: {e}")
        time.sleep(5)
        return texts


def xml_escape(s):
    """Escape for XML attribute values."""
    s = s.replace('&', '&amp;')
    s = s.replace('"', '&quot;')
    s = s.replace('<', '&lt;')
    s = s.replace('>', '&gt;')
    return s


def xml_unescape(s):
    """Unescape XML attribute values for translation."""
    s = s.replace('&amp;', '&')
    s = s.replace('&quot;', '"')
    s = s.replace('&lt;', '<')
    s = s.replace('&gt;', '>')
    return s


def translate_macstrings_only(content, dest_code):
    """Translate only the <MacStrings> section. Preserves all other content."""
    # Find MacStrings section
    mac_match = re.search(r'(<MacStrings>)(.*?)(</MacStrings>)', content, re.DOTALL)
    if not mac_match:
        return content, 0

    mac_section = mac_match.group(2)
    count = 0

    # Find all name="..." in MacStrings items
    items = re.findall(r'(<Item\s+id="[^"]*"\s+name=")([^"]*)("/>)', mac_section)
    if not items:
        return content, 0

    # Collect texts for batch translation
    texts = [xml_unescape(item[1]) for item in items]

    # Batch translate
    batch_size = 25
    all_translations = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        translated = translate_batch(batch, dest_code)
        all_translations.extend(translated)

    # Replace in the MacStrings section
    new_mac = mac_section
    for (prefix, old_name, suffix), new_text in zip(items, all_translations):
        escaped_new = xml_escape(new_text)
        old_full = prefix + old_name + suffix
        new_full = prefix + escaped_new + suffix
        new_mac = new_mac.replace(old_full, new_full, 1)
        count += 1

    new_content = content[:mac_match.start(2)] + new_mac + content[mac_match.end(2):]
    return new_content, count


def translate_full_file(content, dest_code):
    """Translate ALL translatable attributes in the file. Preserves XML structure."""
    count = 0

    # Attributes to translate: name, title, message, value, titleFind, etc.
    # Pattern: attribute="value" where value is English text
    translatable_attrs = [
        'name', 'title', 'message', 'value',
        'titleFind', 'titleReplace', 'titleFindInFiles', 'titleFindInProjects', 'titleMark',
        'alternativeName',
    ]

    # Skip these name values (they're technical, not translatable)
    skip_values = {'', ' ', '0', '1', '2', '3'}

    # Collect ALL translatable strings with their positions
    # We'll do section by section to batch efficiently

    # Strategy: find all attribute="value" pairs, collect English texts,
    # batch translate, then replace in-place

    attr_pattern = re.compile(
        r'(' + '|'.join(translatable_attrs) + r')="([^"]*)"'
    )

    matches = list(attr_pattern.finditer(content))
    if not matches:
        return content, 0

    # Filter: skip empty, numeric, very short technical values
    translatable = []
    for m in matches:
        attr_name = m.group(1)
        value = m.group(2)
        unescaped = xml_unescape(value)

        # Skip empty or very short numeric
        if not unescaped.strip() or unescaped.strip() in skip_values:
            continue
        # Skip if it's just a number
        if re.match(r'^\d+$', unescaped.strip()):
            continue
        # Skip XML/technical looking values
        if unescaped.startswith('$') or unescaped.startswith('@'):
            continue
        # Skip the filename attribute
        if attr_name == 'name' and unescaped.endswith('.xml'):
            continue

        translatable.append((m, attr_name, value, unescaped))

    if not translatable:
        return content, 0

    texts = [t[3] for t in translatable]

    # Batch translate all texts
    all_translations = []
    batch_size = 20
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        translated = translate_batch(batch, dest_code)
        all_translations.extend(translated)
        # Progress
        pct = min(100, int((i + batch_size) / len(texts) * 100))
        print(f"\r      Progress: {pct}% ({i + len(batch)}/{len(texts)})", end="", flush=True)

    print()  # newline after progress

    # Replace from end to start to preserve positions
    result = content
    for (m, attr_name, old_value, _), new_text in reversed(list(zip(translatable, all_translations))):
        escaped_new = xml_escape(new_text)
        # Preserve & accelerator markers for menu items
        old_unescaped = xml_unescape(old_value)
        amp_pos = old_unescaped.find('&')
        if amp_pos >= 0 and attr_name == 'name':
            # Try to re-insert & at roughly the same relative position
            if amp_pos == 0:
                escaped_new = '&amp;' + escaped_new
            elif amp_pos < len(escaped_new):
                escaped_new = escaped_new[:amp_pos] + '&amp;' + escaped_new[amp_pos:]

        old_attr = f'{attr_name}="{old_value}"'
        new_attr = f'{attr_name}="{escaped_new}"'
        # Replace at exact position
        result = result[:m.start()] + new_attr + result[m.end():]
        count += 1

    return result, count


def main():
    if not os.path.isdir(LOC_DIR):
        print(f"Error: {LOC_DIR} not found")
        sys.exit(1)

    xml_files = sorted(f for f in os.listdir(LOC_DIR) if f.endswith('.xml'))
    print(f"Found {len(xml_files)} language files\n")

    global api_calls
    start_time = time.time()
    total_translated = 0
    processed = 0

    for xml_file in xml_files:
        lang_stem = os.path.splitext(xml_file)[0]
        lang_code = LANG_CODES.get(lang_stem)

        if lang_code is None or lang_stem in ('english', 'english_customizable'):
            print(f"  SKIP {xml_file}")
            continue

        xml_path = os.path.join(LOC_DIR, xml_file)
        is_new = lang_stem in NEW_LANGS

        with open(xml_path, 'r', encoding='utf-8') as f:
            content = f.read()

        mode = "FULL" if is_new else "MacStrings"
        processed += 1
        print(f"  [{processed}] {xml_file} ({mode}, {lang_code})...", end=" " if not is_new else "\n", flush=True)

        if is_new:
            new_content, count = translate_full_file(content, lang_code)
        else:
            new_content, count = translate_macstrings_only(content, lang_code)

        with open(xml_path, 'w', encoding='utf-8') as f:
            f.write(new_content)

        total_translated += count
        if not is_new:
            print(f"{count} strings")

    elapsed = time.time() - start_time
    print(f"\nDone!")
    print(f"  Files processed: {processed}")
    print(f"  Strings translated: {total_translated}")
    print(f"  API calls: {api_calls}")
    print(f"  Time: {elapsed/60:.1f} minutes")


if __name__ == '__main__':
    main()
