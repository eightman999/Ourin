#!/usr/bin/env python3
"""
Remove property declarations from extension files (properties must stay in main class).
Add comments indicating where shared properties are declared.
"""

import re

extensions = [
    ('Ourin/Ghost/GhostManager+Window.swift', 'stickyWindowRelationships'),
    ('Ourin/Ghost/GhostManager+System.swift', 'pendingChoices, choiceHasCancelOption, choiceTimeout'),
]

for filepath, props in extensions:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove the Properties MARK section and its contents
    # Pattern: from "// MARK: - Properties" until the next "// MARK:" or start of function
    pattern = r'    // MARK: - Properties\s*\n.*?(?=    // MARK:)'
    content = re.sub(pattern, '', content, flags=re.DOTALL)

    # Add a comment after the extension declaration
    comment = f'''
    // Note: This extension uses the following properties declared in the main GhostManager class:
    // - {props}

'''
    content = content.replace('extension GhostManager {\n', f'extension GhostManager {{{comment}')

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'Fixed {filepath}')

print('\nAll extension files fixed!')
