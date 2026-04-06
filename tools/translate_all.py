#!/usr/bin/env python3
"""
Auto-translate all Notepad++ macOS localization XML files using Google Translate.

Strategy:
1. For 94 EXISTING languages: translate only the 219 MacStrings entries (rest already human-translated)
2. For 43 NEW languages: translate ALL translatable strings (menus, dialogs, MacStrings)

Batches multiple strings per API call to minimize requests.
Adds delays between calls to avoid rate limiting.
"""

import os
import sys
import re
import time
import xml.etree.ElementTree as ET
from googletrans import Translator

LOC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'resources', 'localization')

# googletrans language codes mapped from our filename stems
LANG_CODES = {
    # Existing 94 languages
    "abkhazian": None,  # Not supported by Google
    "afrikaans": "af",
    "albanian": "sq",
    "arabic": "ar",
    "aragonese": None,  # Not supported
    "aranese": None,  # Not supported
    "azerbaijani": "az",
    "basque": "eu",
    "belarusian": "be",
    "bengali": "bn",
    "bosnian": "bs",
    "brazilian_portuguese": "pt",
    "breton": None,  # Not supported
    "bulgarian": "bg",
    "catalan": "ca",
    "chineseSimplified": "zh-cn",
    "corsican": "co",
    "croatian": "hr",
    "czech": "cs",
    "danish": "da",
    "dutch": "nl",
    "english": None,  # Skip
    "english_customizable": None,  # Skip
    "esperanto": "eo",
    "estonian": "et",
    "extremaduran": None,  # Not supported
    "farsi": "fa",
    "finnish": "fi",
    "french": "fr",
    "friulian": None,  # Not supported
    "galician": "gl",
    "georgian": "ka",
    "german": "de",
    "greek": "el",
    "gujarati": "gu",
    "hebrew": "iw",
    "hindi": "hi",
    "hongKongCantonese": "zh-tw",
    "hungarian": "hu",
    "indonesian": "id",
    "irish": "ga",
    "italian": "it",
    "japanese": "ja",
    "kabyle": None,  # Not supported
    "kannada": "kn",
    "kazakh": "kk",
    "korean": "ko",
    "kurdish": "ku",
    "kyrgyz": "ky",
    "latvian": "lv",
    "ligurian": None,  # Not supported
    "lithuanian": "lt",
    "luxembourgish": "lb",
    "macedonian": "mk",
    "malay": "ms",
    "marathi": "mr",
    "mongolian": "mn",
    "nepali": "ne",
    "norwegian": "no",
    "nynorsk": "no",
    "occitan": None,  # Not supported
    "piglatin": None,  # Not a real language
    "polish": "pl",
    "portuguese": "pt",
    "punjabi": "pa",
    "romanian": "ro",
    "russian": "ru",
    "samogitian": None,  # Not supported
    "sardinian": None,  # Not supported
    "serbian": "sr",
    "serbianCyrillic": "sr",
    "sinhala": "si",
    "slovak": "sk",
    "slovenian": "sl",
    "spanish": "es",
    "spanish_ar": "es",
    "swedish": "sv",
    "tagalog": "tl",
    "taiwaneseMandarin": "zh-tw",
    "tajikCyrillic": "tg",
    "tamil": "ta",
    "tatar": None,  # Limited support
    "telugu": "te",
    "thai": "th",
    "turkish": "tr",
    "ukrainian": "uk",
    "urdu": "ur",
    "uyghur": "ug",
    "uzbek": "uz",
    "uzbekCyrillic": "uz",
    "venetian": None,  # Not supported
    "vietnamese": "vi",
    "welsh": "cy",
    "zulu": "zu",
    # New 43 languages
    "amharic": "am",
    "armenian": "hy",
    "assamese": None,  # Limited
    "aymara": "ay",
    "bambara": "bm",
    "bhojpuri": "bho",
    "cebuano": "ceb",
    "chichewa": "ny",
    "dhivehi": "dv",
    "dogri": "doi",
    "ewe": "ee",
    "guarani": "gn",
    "hausa": "ha",
    "hawaiian": "haw",
    "hmong": "hmn",
    "igbo": "ig",
    "ilocano": "ilo",
    "javanese": "jw",
    "kinyarwanda": "rw",
    "konkani": "gom",
    "krio": "kri",
    "lao": "lo",
    "lingala": "ln",
    "maithili": "mai",
    "malagasy": "mg",
    "malayalam": "ml",
    "mizo": "lus",
    "myanmar": "my",
    "odia": "or",
    "pashto": "ps",
    "quechua": "qu",
    "sepedi": "nso",
    "sesotho": "st",
    "shona": "sn",
    "somali": "so",
    "sundanese": "su",
    "swahili": "sw",
    "tigrinya": "ti",
    "tsonga": "ts",
    "turkmen": "tk",
    "twi": "ak",
    "xhosa": "xh",
    "yoruba": "yo",
}

# Files that were created from English template (need full translation)
NEW_LANGUAGE_FILES = {
    "amharic", "armenian", "assamese", "aymara", "bambara", "bhojpuri",
    "cebuano", "chichewa", "dhivehi", "dogri", "ewe", "guarani", "hausa",
    "hawaiian", "hmong", "igbo", "ilocano", "javanese", "kinyarwanda",
    "konkani", "krio", "lao", "lingala", "maithili", "malagasy", "malayalam",
    "mizo", "myanmar", "odia", "pashto", "quechua", "sepedi", "sesotho",
    "shona", "somali", "sundanese", "swahili", "tigrinya", "tsonga",
    "turkmen", "twi", "xhosa", "yoruba",
}

translator = Translator()
call_count = 0
DELAY = 1.0  # seconds between API calls


def translate_batch(texts, dest_lang):
    """Translate a batch of texts. Returns list of translated strings."""
    global call_count
    if not texts:
        return []

    # Join with a delimiter that won't appear in UI strings
    delimiter = " ||| "
    combined = delimiter.join(texts)

    # Limit to ~4500 chars per call
    if len(combined) > 4500:
        mid = len(texts) // 2
        return translate_batch(texts[:mid], dest_lang) + translate_batch(texts[mid:], dest_lang)

    try:
        time.sleep(DELAY)
        call_count += 1
        result = translator.translate(combined, dest=dest_lang, src='en')
        translated = result.text

        # Split back
        parts = translated.split("|||")
        # Clean up whitespace around delimiters
        parts = [p.strip() for p in parts]

        # If split count doesn't match, fall back to originals
        if len(parts) != len(texts):
            # Try with just | as delimiter might have been eaten
            parts2 = translated.split("|")
            parts2 = [p.strip() for p in parts2 if p.strip()]
            if len(parts2) == len(texts):
                parts = parts2
            else:
                print(f"    WARNING: batch mismatch ({len(parts)} vs {len(texts)}), using originals")
                return texts

        return parts
    except Exception as e:
        print(f"    ERROR: {e}")
        time.sleep(5)  # Back off on error
        return texts  # Return originals on failure


def translate_xml_file(xml_path, lang_stem, lang_code, full_translate=False):
    """Translate strings in an XML file."""
    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()

    tree = ET.parse(xml_path)
    root = tree.getroot()
    nl = root.find('.//Native-Langue')
    if nl is None:
        return 0

    translated_count = 0

    if full_translate:
        # Translate ALL name attributes in Item elements
        sections = [
            ('Menu/Main/Entries/Item', 'name'),
            ('Menu/Main/SubEntries/Item', 'name'),
            ('Menu/Main/Commands/Item', 'name'),
            ('Menu/TabBar/Item', 'name'),
        ]

        for xpath, attr in sections:
            items = nl.findall(xpath)
            if not items:
                continue

            # Collect texts to translate
            texts = []
            elements = []
            for item in items:
                val = item.get(attr, '')
                if val and val.strip():
                    # Strip & accelerator markers for translation, re-add after
                    clean = val.replace('&', '')
                    texts.append(clean)
                    elements.append((item, attr, val))

            if not texts:
                continue

            # Batch translate
            batch_size = 20
            for i in range(0, len(texts), batch_size):
                batch_texts = texts[i:i + batch_size]
                batch_elements = elements[i:i + batch_size]
                translations = translate_batch(batch_texts, lang_code)

                for (elem, attr_name, original), trans in zip(batch_elements, translations):
                    # Re-add & accelerator at original position
                    amp_pos = original.find('&')
                    if amp_pos >= 0 and amp_pos < len(trans):
                        trans = trans[:amp_pos] + '&' + trans[amp_pos:]
                    elif amp_pos >= 0:
                        trans = '&' + trans
                    elem.set(attr_name, trans)
                    translated_count += 1

        # Also translate dialog titles and item names
        dialog = nl.find('Dialog')
        if dialog is not None:
            all_items = list(dialog.iter('Item'))
            texts = []
            elements = []
            for item in all_items:
                name = item.get('name', '')
                if name and name.strip():
                    clean = name.replace('&', '')
                    texts.append(clean)
                    elements.append((item, name))

            batch_size = 20
            for i in range(0, len(texts), batch_size):
                batch_texts = texts[i:i + batch_size]
                batch_elements = elements[i:i + batch_size]
                translations = translate_batch(batch_texts, lang_code)

                for (elem, original), trans in zip(batch_elements, translations):
                    amp_pos = original.find('&')
                    if amp_pos >= 0 and amp_pos < len(trans):
                        trans = trans[:amp_pos] + '&' + trans[amp_pos:]
                    elif amp_pos >= 0:
                        trans = '&' + trans
                    elem.set('name', trans)
                    translated_count += 1

            # Translate dialog title attributes
            for elem in dialog.iter():
                for attr_name in ['title', 'titleFind', 'titleReplace', 'titleFindInFiles',
                                  'titleFindInProjects', 'titleMark']:
                    val = elem.get(attr_name, '')
                    if val and val.strip():
                        try:
                            time.sleep(DELAY)
                            result = translator.translate(val, dest=lang_code, src='en')
                            elem.set(attr_name, result.text)
                            translated_count += 1
                        except:
                            pass

    else:
        # Only translate MacStrings section
        dialog = nl.find('Dialog')
        if dialog is None:
            return 0

        mac_strings = dialog.find('MacStrings')
        if mac_strings is None:
            return 0

        items = list(mac_strings.findall('Item'))
        texts = []
        elements = []
        for item in items:
            name = item.get('name', '')
            if name and name.strip():
                texts.append(name)
                elements.append(item)

        # Batch translate
        batch_size = 20
        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i:i + batch_size]
            batch_elements = elements[i:i + batch_size]
            translations = translate_batch(batch_texts, lang_code)

            for elem, trans in zip(batch_elements, translations):
                elem.set('name', trans)
                translated_count += 1

    # Write back - use ET to preserve structure
    tree.write(xml_path, encoding='utf-8', xml_declaration=True)

    # Fix ET's output: add newlines for readability
    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()
    # Ensure proper XML declaration
    if not content.startswith('<?xml'):
        content = '<?xml version="1.0" encoding="utf-8" ?>\n' + content

    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write(content)

    return translated_count


def main():
    if not os.path.isdir(LOC_DIR):
        print(f"Error: {LOC_DIR} not found")
        sys.exit(1)

    xml_files = sorted(f for f in os.listdir(LOC_DIR) if f.endswith('.xml'))
    print(f"Found {len(xml_files)} language files")

    global call_count
    start_time = time.time()
    total_translated = 0
    processed = 0
    skipped = 0

    for xml_file in xml_files:
        lang_stem = os.path.splitext(xml_file)[0]
        lang_code = LANG_CODES.get(lang_stem)

        if lang_code is None:
            print(f"  SKIP {xml_file} (no Google Translate code)")
            skipped += 1
            continue

        if lang_stem in ('english', 'english_customizable'):
            continue

        xml_path = os.path.join(LOC_DIR, xml_file)
        is_new = lang_stem in NEW_LANGUAGE_FILES

        mode = "FULL" if is_new else "MacStrings only"
        print(f"  [{processed+1}] {xml_file} ({mode}, code={lang_code})...", end=" ", flush=True)

        count = translate_xml_file(xml_path, lang_stem, lang_code, full_translate=is_new)
        total_translated += count
        processed += 1
        print(f"{count} strings translated")

    elapsed = time.time() - start_time
    print(f"\nDone!")
    print(f"  Processed: {processed} files")
    print(f"  Skipped: {skipped} files (unsupported by Google Translate)")
    print(f"  Total strings translated: {total_translated}")
    print(f"  API calls: {call_count}")
    print(f"  Time: {elapsed/60:.1f} minutes")


if __name__ == '__main__':
    main()
