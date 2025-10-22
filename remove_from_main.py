#!/usr/bin/env python3
"""
Remove extracted sections from the main GhostManager.swift file.
"""

# Read the original file
with open('Ourin/Ghost/GhostManager.swift', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Define ranges to remove (in reverse order to preserve line numbers)
ranges_to_remove = [
    (2690, 2750),  # Display - Desktop Alignment
    (2570, 2690),  # Effects
    (2275, 2569),  # Window - Position Control
    (2073, 2274),  # System - System Commands
    (1910, 1992),  # Surface - Compositing
    (1869, 1909),  # Balloon - Image Display
    (1752, 1868),  # System - Choice Command
    (1648, 1751),  # System - Ghost Booting
    (1601, 1647),  # Display - Email Handling
    (1560, 1600),  # Display - Sound Playback
    (1518, 1559),  # Display - Configuration Dialog
    (1442, 1517),  # Display - Ghost Configuration
    (1369, 1441),  # Balloon - Positioning
    (1284, 1368),  # Surface - updateSurface
    (1124, 1214),  # Balloon - helpers
    (1993, 2072),  # Animation
    (309, 403),    # Window - Setup
]

# Sort ranges in reverse order by start line
ranges_to_remove.sort(key=lambda x: x[0], reverse=True)

# Remove the lines (working backwards to preserve line numbers)
for start, end in ranges_to_remove:
    # Convert to 0-indexed and remove
    del lines[start-1:end]

# Write back to file
with open('Ourin/Ghost/GhostManager.swift', 'w', encoding='utf-8') as f:
    f.writelines(lines)

print('Removed extracted sections from GhostManager.swift')
print(f'New file size: {len(lines)} lines (was 2780 lines)')
