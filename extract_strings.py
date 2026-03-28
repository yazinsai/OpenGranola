#!/usr/bin/env python3
"""
Extract hardcoded strings from Swift files for i18n.
Looks for Text("..."), Label("..."), Button("..."), etc.
"""

import os
import re
import json
from pathlib import Path

def extract_strings_from_swift(file_path):
    """Extract localizable strings from a Swift file."""
    strings = []
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Patterns for different UI elements
    patterns = [
        r'Text\("([^"]+)"\)',                    # Text("string")
        r'Label\("([^"]+)",',                    # Label("string",
        r'Button\("([^"]+)"\)',                  # Button("string")
        r'\.navigationTitle\("([^"]+)"\)',       # .navigationTitle("string")
        r'\.title\("([^"]+)"\)',                 # .title("string")
        r'\.help\("([^"]+)"\)',                  # .help("string")
        r'alert\.messageText = "([^"]+)"',       # NSAlert messageText
        r'alert\.informativeText = "([^"]+)"',   # NSAlert informativeText
        r'alert\.addButton\(withTitle: "([^"]+)"\)', # NSAlert button
        r'content\.title = "([^"]+)"',           # notification title
        r'content\.body = "([^"]+)"',            # notification body
        r'panel\.title = "([^"]+)"',             # NSOpenPanel title
        r'panel\.message = "([^"]+)"',           # NSOpenPanel message
    ]
    
    for pattern in patterns:
        matches = re.finditer(pattern, content)
        for match in matches:
            string_value = match.group(1)
            line_num = content[:match.start()].count('\n') + 1
            
            # Skip certain strings that shouldn't be localized
            if should_localize(string_value):
                strings.append({
                    'value': string_value,
                    'line': line_num,
                    'file': file_path,
                    'context': get_context(content, match.start(), match.end())
                })
    
    return strings

def should_localize(string_value):
    """Determine if a string should be localized."""
    # Skip empty strings
    if not string_value.strip():
        return False
        
    # Skip technical identifiers
    technical_patterns = [
        r'^[a-z]+\.[a-z]+(\.[a-z]+)*$',  # system image names like "doc.text"
        r'^http[s]?://',                 # URLs
        r'^\w+://.*',                    # URL schemes
        r'^[A-Z_]+$',                    # Constants like "SUGGESTIONS"
        r'^\d+(\.\d+)*$',               # Version numbers
        r'^[\w\.-]+@[\w\.-]+$',         # Email addresses
        r'^\$\w+',                      # Environment variables like "$PATH"
        r'^\w+\.\w+',                   # File extensions or config keys
    ]
    
    for pattern in technical_patterns:
        if re.match(pattern, string_value):
            return False
    
    # Skip very short strings that are likely technical
    if len(string_value) <= 2:
        return False
        
    return True

def get_context(content, start, end):
    """Get context around the match for better understanding."""
    lines = content.split('\n')
    line_num = content[:start].count('\n')
    
    # Get the line with some context
    context_start = max(0, line_num - 1)
    context_end = min(len(lines), line_num + 2)
    
    return '\n'.join(lines[context_start:context_end])

def main():
    swift_files = []
    source_dir = Path('OpenOats/Sources')
    
    # Find all Swift files, excluding tests
    for swift_file in source_dir.rglob('*.swift'):
        if 'Tests' not in str(swift_file):
            swift_files.append(swift_file)
    
    all_strings = []
    file_stats = {}
    
    for swift_file in swift_files:
        print(f"Processing {swift_file}")
        strings = extract_strings_from_swift(swift_file)
        file_stats[str(swift_file)] = len(strings)
        all_strings.extend(strings)
    
    # Sort by file and line number
    all_strings.sort(key=lambda x: (x['file'], x['line']))
    
    # Generate key from string value
    def generate_key(string_value, index):
        # Clean the string to create a reasonable key
        key = string_value.lower()
        key = re.sub(r'[^\w\s]', '', key)  # Remove punctuation
        key = re.sub(r'\s+', '_', key.strip())  # Replace spaces with underscores
        key = key[:50]  # Limit length
        
        # If empty or too short, use a generic key
        if len(key) < 3:
            key = f"string_{index}"
            
        return key
    
    # Create Localizable.strings content
    localizable_content = []
    keys_used = set()
    
    print(f"\nFound {len(all_strings)} localizable strings")
    print("\nGenerating Localizable.strings...")
    
    for i, string_info in enumerate(all_strings):
        string_value = string_info['value']
        base_key = generate_key(string_value, i)
        
        # Ensure unique keys
        key = base_key
        counter = 1
        while key in keys_used:
            key = f"{base_key}_{counter}"
            counter += 1
        keys_used.add(key)
        
        # Add to localizable content
        localizable_content.append(f'// {string_info["file"]}:{string_info["line"]}')
        localizable_content.append(f'"{key}" = "{string_value}";')
        localizable_content.append('')  # Empty line
    
    # Write Localizable.strings file
    os.makedirs('OpenOats/en.lproj', exist_ok=True)
    with open('OpenOats/en.lproj/Localizable.strings', 'w', encoding='utf-8') as f:
        f.write('\n'.join(localizable_content))
    
    # Generate summary report
    print("\nFile Statistics:")
    for file_path, count in sorted(file_stats.items()):
        if count > 0:
            print(f"  {file_path}: {count} strings")
    
    print(f"\nGenerated OpenOats/en.lproj/Localizable.strings with {len(all_strings)} strings")
    
    # Save detailed extraction info for reference (convert Path objects to strings)
    serializable_strings = []
    for string_info in all_strings:
        serializable_info = string_info.copy()
        serializable_info['file'] = str(serializable_info['file'])
        serializable_strings.append(serializable_info)
    
    with open('OpenOats/string_extraction_report.json', 'w', encoding='utf-8') as f:
        json.dump(serializable_strings, f, indent=2, ensure_ascii=False)
    
    print("Saved detailed report to OpenOats/string_extraction_report.json")

if __name__ == '__main__':
    main()