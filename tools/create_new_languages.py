#!/usr/bin/env python3
"""
Create new language XML files for Notepad++ macOS by copying the English XML
structure and replacing translatable strings.

Since we can't call Google Translate API directly, this script creates
language files with the English XML structure but native language name
in the header. The menu/dialog strings remain in English as placeholders
until community translators update them.

The key benefit: the file structure is correct, the MacStrings section
is included, and the language appears in the Preferences dropdown.
"""

import os
import re
import shutil

LOC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       'resources', 'localization')

# New languages to add: (filename_stem, display_name, native_name)
NEW_LANGUAGES = [
    ("amharic", "Amharic", "አማርኛ"),
    ("armenian", "Armenian", "Հայերեն"),
    ("assamese", "Assamese", "অসমীয়া"),
    ("aymara", "Aymara", "Aymar aru"),
    ("bambara", "Bambara", "Bamanankan"),
    ("bhojpuri", "Bhojpuri", "भोजपुरी"),
    ("cebuano", "Cebuano", "Cebuano"),
    ("chichewa", "Chichewa", "Chichewa"),
    ("dhivehi", "Dhivehi", "ދިވެހި"),
    ("dogri", "Dogri", "डोगरी"),
    ("ewe", "Ewe", "Eʋegbe"),
    ("guarani", "Guarani", "Avañe'ẽ"),
    ("hausa", "Hausa", "Hausa"),
    ("hawaiian", "Hawaiian", "ʻŌlelo Hawaiʻi"),
    ("hmong", "Hmong", "Hmoob"),
    ("igbo", "Igbo", "Igbo"),
    ("ilocano", "Ilocano", "Ilokano"),
    ("javanese", "Javanese", "Basa Jawa"),
    ("kinyarwanda", "Kinyarwanda", "Ikinyarwanda"),
    ("konkani", "Konkani", "कोंकणी"),
    ("krio", "Krio", "Krio"),
    ("lao", "Lao", "ລາວ"),
    ("lingala", "Lingala", "Lingála"),
    ("maithili", "Maithili", "मैथिली"),
    ("malagasy", "Malagasy", "Malagasy"),
    ("malayalam", "Malayalam", "മലയാളം"),
    ("mizo", "Mizo", "Mizo ṭawng"),
    ("myanmar", "Myanmar (Burmese)", "မြန်မာ"),
    ("odia", "Odia", "ଓଡ଼ିଆ"),
    ("pashto", "Pashto", "پښتو"),
    ("quechua", "Quechua", "Runasimi"),
    ("sepedi", "Sepedi", "Sepedi"),
    ("sesotho", "Sesotho", "Sesotho"),
    ("shona", "Shona", "chiShona"),
    ("somali", "Somali", "Soomaali"),
    ("sundanese", "Sundanese", "Basa Sunda"),
    ("swahili", "Swahili", "Kiswahili"),
    ("tigrinya", "Tigrinya", "ትግርኛ"),
    ("tsonga", "Tsonga", "Xitsonga"),
    ("turkmen", "Turkmen", "Türkmen"),
    ("twi", "Twi", "Twi"),
    ("xhosa", "Xhosa", "isiXhosa"),
    ("yoruba", "Yoruba", "Yorùbá"),
]

# RTL languages (need RTL="yes" attribute)
RTL_LANGUAGES = {"pashto", "dhivehi"}


def create_language_file(stem, display_name, native_name):
    """Create a new language XML file from the English template."""
    eng_path = os.path.join(LOC_DIR, 'english.xml')
    new_path = os.path.join(LOC_DIR, f'{stem}.xml')

    if os.path.exists(new_path):
        return f'skipped (already exists)'

    with open(eng_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace the language name in the header
    # Original: <Native-Langue name="English" filename="english.xml" ...>
    content = re.sub(
        r'<Native-Langue\s+name="[^"]*"\s+filename="[^"]*"',
        f'<Native-Langue name="{native_name}" filename="{stem}.xml"',
        content
    )

    # Add RTL attribute if needed
    if stem in RTL_LANGUAGES:
        content = content.replace(
            f'filename="{stem}.xml"',
            f'filename="{stem}.xml" RTL="yes"'
        )

    # Update the comment header
    old_comment = re.search(r'<!--.*?-->', content, re.DOTALL)
    if old_comment:
        new_comment = f'''<!--
    {display_name} ({native_name}) language file for Notepad++ macOS
    Based on English template - community translations welcome
    Created: 2026-04-04
-->'''
        content = content[:old_comment.start()] + new_comment + content[old_comment.end():]

    with open(new_path, 'w', encoding='utf-8') as f:
        f.write(content)

    return 'created'


def main():
    if not os.path.isdir(LOC_DIR):
        print(f"Error: {LOC_DIR} not found")
        return

    eng_path = os.path.join(LOC_DIR, 'english.xml')
    if not os.path.exists(eng_path):
        print(f"Error: {eng_path} not found")
        return

    print(f"Creating {len(NEW_LANGUAGES)} new language files...\n")

    created = 0
    skipped = 0
    for stem, display, native in NEW_LANGUAGES:
        result = create_language_file(stem, display, native)
        print(f"  {stem}.xml: {result} ({native})")
        if 'created' in result:
            created += 1
        else:
            skipped += 1

    print(f"\nDone: {created} created, {skipped} skipped")

    # Count total
    total = len([f for f in os.listdir(LOC_DIR) if f.endswith('.xml')])
    print(f"Total language files: {total}")


if __name__ == '__main__':
    main()
