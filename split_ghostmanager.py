#!/usr/bin/env python3
"""
Split GhostManager.swift into multiple extension files by category.
"""

import re

# Read the original file
with open('Ourin/Ghost/GhostManager.swift', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Extract imports (lines 1-6)
imports = ''.join(lines[0:6])

# Define split sections with line ranges (1-indexed)
sections = {
    'Window': {
        'ranges': [(309, 403), (2275, 2569)],
        'description': 'Window Setup and Position Control',
        'properties': ['stickyWindowRelationships']
    },
    'Balloon': {
        'ranges': [(1124, 1214), (1369, 1441), (1869, 1909)],
        'description': 'Balloon Management and Positioning',
        'properties': []
    },
    'Animation': {
        'ranges': [(1993, 2072)],
        'description': 'Animation Engine Integration',
        'properties': []
    },
    'Surface': {
        'ranges': [(1284, 1368), (1910, 1992)],
        'description': 'Surface Loading and Compositing',
        'properties': []
    },
    'System': {
        'ranges': [(1648, 1751), (1752, 1868), (2073, 2274)],
        'description': 'System Commands and Ghost Booting',
        'properties': ['pendingChoices', 'choiceHasCancelOption', 'choiceTimeout']
    },
    'Effects': {
        'ranges': [(2570, 2690)],
        'description': 'Effects, Filters, Dressup, and Text Animations',
        'properties': []
    },
    'Display': {
        'ranges': [(1442, 1517), (1518, 1559), (1560, 1600), (1601, 1647), (2690, 2750)],
        'description': 'Display Settings and Desktop Alignment',
        'properties': []
    },
}

# Helper to extract lines
def extract_lines(ranges):
    result = []
    for start, end in ranges:
        # Convert to 0-indexed
        result.extend(lines[start-1:end])
    return ''.join(result)

# Helper to find and extract property declarations
def extract_property_lines(prop_names):
    if not prop_names:
        return ''

    result = []
    in_class = False
    for i, line in enumerate(lines):
        if 'class GhostManager' in line:
            in_class = True
        elif in_class and line.strip().startswith('//'):
            continue
        elif in_class:
            for prop in prop_names:
                if f'{prop}:' in line or f'{prop} ' in line:
                    # Include this line and handle multi-line declarations
                    result.append(line)
                    # Check if next lines are part of same declaration
                    j = i + 1
                    while j < len(lines) and not lines[j].strip().startswith(('var', 'let', 'private', 'func', '//')):
                        result.append(lines[j])
                        j += 1
                        if lines[j-1].strip().endswith('}'):
                            break

    if result:
        return '\n    // MARK: - Properties\n    \n' + ''.join(result) + '\n'
    return ''

# Create extension files
for category, config in sections.items():
    filename = f'Ourin/Ghost/GhostManager+{category}.swift'
    content = extract_lines(config['ranges'])
    properties = extract_property_lines(config['properties'])

    # Build the extension file
    extension_content = f'''{imports}
// MARK: - {config['description']}

extension GhostManager {{
{properties}{content}}}
'''

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(extension_content)

    print(f'Created {filename}')

print('\nAll extension files created successfully!')
print('\nNext steps:')
print('1. Remove the extracted code from the original GhostManager.swift')
print('2. Add the new files to Xcode project')
print('3. Build and test')
