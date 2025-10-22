#!/usr/bin/env python3
"""
Fix access modifiers in extension files.
"""

import glob

extension_files = glob.glob('Ourin/Ghost/GhostManager+*.swift')

for filepath in extension_files:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Fix @objc private func
    content = content.replace('@objc private func', '@objc fileprivate func')

    # Fix private func in extensions
    content = content.replace('    private func', '    fileprivate func')

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'Fixed {filepath}')

print('\nAll extension files fixed!')
