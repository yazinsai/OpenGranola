#!/usr/bin/env python3
"""
Replace hardcoded strings in Swift files with String(localized:) calls.
"""

import os
import re
import json
from pathlib import Path

def load_string_mappings():
    """Load the string mappings from extraction report."""
    with open('OpenOats/string_extraction_report.json', 'r') as f:
        data = json.load(f)
    
    # Create mapping from original string to key
    mapping = {}
    for item in data:
        mapping[item['value']] = item
    
    return mapping

def replace_strings_in_file(file_path, mappings):
    """Replace hardcoded strings in a file with String(localized:) calls."""
    
    # Read the file
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    replacements = []
    
    # Pattern definitions with their replacement templates
    patterns_and_replacements = [
        # Text("string") -> Text(String(localized: "key"))
        (r'Text\("([^"]+)"\)', r'Text(String(localized: "{key}"))'),
        
        # Label("string", -> Label(String(localized: "key"),
        (r'Label\("([^"]+)",', r'Label(String(localized: "{key}"),'),
        
        # Button("string") -> Button(String(localized: "key"))
        (r'Button\("([^"]+)"\)', r'Button(String(localized: "{key}"))'),
        
        # .help("string") -> .help(String(localized: "key"))
        (r'\.help\("([^"]+)"\)', r'.help(String(localized: "{key}"))'),
        
        # NSAlert patterns
        (r'alert\.messageText = "([^"]+)"', r'alert.messageText = String(localized: "{key}")'),
        (r'alert\.informativeText = "([^"]+)"', r'alert.informativeText = String(localized: "{key}")'),
        (r'alert\.addButton\(withTitle: "([^"]+)"\)', r'alert.addButton(withTitle: String(localized: "{key}"))'),
        
        # Notification patterns
        (r'content\.title = "([^"]+)"', r'content.title = String(localized: "{key}")'),
        (r'content\.body = "([^"]+)"', r'content.body = String(localized: "{key}")'),
        
        # Panel patterns
        (r'panel\.title = "([^"]+)"', r'panel.title = String(localized: "{key}")'),
        (r'panel\.message = "([^"]+)"', r'panel.message = String(localized: "{key}")'),
        
        # Navigation patterns
        (r'\.navigationTitle\("([^"]+)"\)', r'.navigationTitle(String(localized: "{key}"))'),
        (r'\.title\("([^"]+)"\)', r'.title(String(localized: "{key}"))'),
    ]
    
    for pattern, replacement_template in patterns_and_replacements:
        matches = list(re.finditer(pattern, content))
        # Process matches in reverse order to avoid offset issues
        for match in reversed(matches):
            string_value = match.group(1)
            
            if string_value in mappings:
                # Find the key for this string
                key = find_key_for_string(string_value, mappings)
                if key:
                    replacement = replacement_template.replace('{key}', key)
                    start, end = match.span()
                    content = content[:start] + replacement + content[end:]
                    replacements.append({
                        'original': match.group(0),
                        'replacement': replacement,
                        'line': original_content[:start].count('\n') + 1
                    })
    
    # Only write if changes were made
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return replacements
    
    return []

def find_key_for_string(string_value, mappings):
    """Find the localization key for a string value."""
    if string_value in mappings:
        # Load the actual Localizable.strings to get the key
        with open('OpenOats/en.lproj/Localizable.strings', 'r') as f:
            localizable_content = f.read()
        
        # Find the key for this string value
        pattern = rf'"([^"]+)" = "{re.escape(string_value)}";'
        match = re.search(pattern, localizable_content)
        if match:
            return match.group(1)
    
    return None

def main():
    # Load string mappings
    mappings = load_string_mappings()
    
    # Process all Swift files
    swift_files = []
    source_dir = Path('OpenOats/Sources')
    
    for swift_file in source_dir.rglob('*.swift'):
        if 'Tests' not in str(swift_file):
            swift_files.append(swift_file)
    
    total_replacements = 0
    file_stats = {}
    
    for swift_file in swift_files:
        print(f"Processing {swift_file}")
        replacements = replace_strings_in_file(swift_file, mappings)
        if replacements:
            file_stats[str(swift_file)] = len(replacements)
            total_replacements += len(replacements)
            print(f"  Made {len(replacements)} replacements")
    
    print(f"\nSummary:")
    print(f"Total replacements: {total_replacements}")
    print(f"Files modified: {len(file_stats)}")
    
    for file_path, count in sorted(file_stats.items()):
        print(f"  {file_path}: {count} replacements")

if __name__ == '__main__':
    main()