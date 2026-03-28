#!/usr/bin/env python3
"""
Translate English strings to Swedish using DeepL API.
Uses du-tilltal and follows Språkrådet guidelines.
"""

import re
import requests
import json
import time

def parse_localizable_strings(file_path):
    """Parse a Localizable.strings file and extract key-value pairs."""
    strings = {}
    comments = {}
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    current_comment = None
    
    for line in lines:
        line = line.strip()
        
        # Comment line
        if line.startswith('//'):
            current_comment = line
        
        # String line: "key" = "value";
        elif '=' in line and line.endswith(';'):
            match = re.match(r'"([^"]+)"\s*=\s*"([^"]+)";', line)
            if match:
                key = match.group(1)
                value = match.group(2)
                strings[key] = value
                if current_comment:
                    comments[key] = current_comment
                    current_comment = None
    
    return strings, comments

def translate_text_deepl(text, api_key, source_lang='EN', target_lang='SV'):
    """Translate text using DeepL API."""
    
    url = 'https://api-free.deepl.com/v2/translate'
    
    headers = {
        'Authorization': f'DeepL-Auth-Key {api_key}',
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    
    data = {
        'text': text,
        'source_lang': source_lang,
        'target_lang': target_lang,
        'formality': 'default'  # Use du-tilltal (informal) as default
    }
    
    try:
        response = requests.post(url, headers=headers, data=data)
        response.raise_for_status()
        
        result = response.json()
        return result['translations'][0]['text']
        
    except requests.exceptions.RequestException as e:
        print(f"Error translating '{text}': {e}")
        return None

def improve_swedish_translation(original_english, machine_translation):
    """Improve Swedish translation following Språkrådet guidelines."""
    
    # Common UI translation improvements
    improvements = {
        # Technical terms that should not be translated
        'OpenOats': 'OpenOats',  # Keep app name
        'GitHub': 'GitHub',      # Keep service names
        'API': 'API',
        'URL': 'URL',
        'macOS': 'macOS',
        'VoiceOver': 'VoiceOver',
        'WCAG': 'WCAG',
        
        # Common UI patterns
        'Välj...': 'Välj...',
        'Avbryt': 'Avbryt', 
        'OK': 'OK',
        'Spara': 'Spara',
        'Radera': 'Ta bort',
        'Inställningar': 'Inställningar',
        'Hjälp': 'Hjälp',
        'Mer': 'Mer',
        
        # Swedish tech conventions
        'loggar': 'loggar',
        'cache': 'cache',
        'backup': 'backup',
        'export': 'exportera',
        'import': 'importera',
        
        # Du-tilltal consistency
        'Du kan': 'Du kan',
        'ditt': 'ditt',
        'din': 'din',
        'dina': 'dina',
    }
    
    improved = machine_translation
    
    # Apply improvements
    for eng_term, swe_term in improvements.items():
        if eng_term.lower() in original_english.lower():
            # Case-sensitive replacement
            improved = improved.replace(eng_term, swe_term)
    
    # Fix common Swedish grammar issues
    improved = re.sub(r'\bdu\b', 'du', improved)  # Lowercase du (informal)
    improved = re.sub(r'\bDu\b(?!\s+)', 'Du', improved)  # Capitalize at sentence start
    
    # Swedish punctuation preferences
    improved = improved.replace('...', '…')
    
    return improved

def translate_strings_to_swedish(strings, api_key):
    """Translate all strings to Swedish with improvements."""
    
    translated = {}
    total = len(strings)
    
    print(f"Translating {total} strings to Swedish...")
    
    for i, (key, english_text) in enumerate(strings.items(), 1):
        print(f"[{i}/{total}] Translating: {english_text[:50]}...")
        
        # Handle special cases
        if not english_text.strip():
            translated[key] = english_text
            continue
            
        # Skip technical strings that shouldn't be translated
        if should_skip_translation(english_text):
            translated[key] = english_text
            continue
        
        # Translate with DeepL
        machine_translation = translate_text_deepl(english_text, api_key)
        
        if machine_translation:
            # Improve the translation
            improved = improve_swedish_translation(english_text, machine_translation)
            translated[key] = improved
            
            print(f"  EN: {english_text}")
            print(f"  SV: {improved}")
            print()
        else:
            # Fallback to original if translation fails
            translated[key] = english_text
            print(f"  Failed to translate, keeping original: {english_text}")
        
        # Rate limiting - DeepL free tier allows 500,000 chars/month
        time.sleep(0.1)
    
    return translated

def should_skip_translation(text):
    """Check if text should not be translated."""
    skip_patterns = [
        r'^[a-z]+\.[a-z]+(\.[a-z]+)*$',  # system image names
        r'^http[s]?://',                 # URLs
        r'^\$\w+',                      # Environment variables
        r'^\d+(\.\d+)*$',               # Version numbers
        r'^[A-Z_]+$',                   # ALL_CAPS constants
        r'^\w+://.*',                   # URL schemes
    ]
    
    for pattern in skip_patterns:
        if re.match(pattern, text):
            return True
    
    # Skip very short technical strings
    if len(text) <= 2 and text.isupper():
        return True
        
    return False

def generate_swedish_localizable(strings, comments, output_path):
    """Generate Swedish Localizable.strings file."""
    
    lines = []
    
    for key in strings:
        if key in comments:
            lines.append(comments[key])
        
        swedish_value = strings[key]
        # Escape quotes in the value
        escaped_value = swedish_value.replace('"', '\\"')
        
        lines.append(f'"{key}" = "{escaped_value}";')
        lines.append('')  # Empty line
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

def main():
    api_key = '97e56d9e-b3a3-4d5f-b975-cd82ea60cc23'
    
    # Parse English strings
    print("Loading English strings...")
    english_strings, comments = parse_localizable_strings('OpenOats/en.lproj/Localizable.strings')
    print(f"Loaded {len(english_strings)} strings")
    
    # Translate to Swedish
    swedish_strings = translate_strings_to_swedish(english_strings, api_key)
    
    # Generate Swedish Localizable.strings
    output_path = 'OpenOats/sv.lproj/Localizable.strings'
    print(f"Writing Swedish strings to {output_path}...")
    generate_swedish_localizable(swedish_strings, comments, output_path)
    
    print("Swedish translation complete!")
    
    # Generate summary
    translated_count = sum(1 for k, v in swedish_strings.items() 
                          if v != english_strings[k])
    
    print(f"\nSummary:")
    print(f"  Total strings: {len(english_strings)}")
    print(f"  Translated: {translated_count}")
    print(f"  Kept original: {len(english_strings) - translated_count}")

if __name__ == '__main__':
    main()