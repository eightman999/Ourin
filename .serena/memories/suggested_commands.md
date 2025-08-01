# Suggested Commands for Development

## Build Commands
```bash
# Build the project
xcodebuild -project Ourin.xcodeproj -scheme Ourin build

# Clean build
xcodebuild -project Ourin.xcodeproj -scheme Ourin clean

# Build for release
xcodebuild -project Ourin.xcodeproj -scheme Ourin -configuration Release build
```

## Testing Commands
```bash
# Run all tests
xcodebuild -project Ourin.xcodeproj -scheme Ourin test

# Run specific test class
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/TestClassName test

# Run specific test method
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/TestClassName/testMethodName test
```

## Running the Application
```bash
# Build and run (requires Xcode)
open Ourin.xcodeproj

# Build and launch app bundle
xcodebuild -project Ourin.xcodeproj -scheme Ourin build && open build/Release/Ourin.app
```

## Development Utilities
```bash
# Standard macOS commands work
ls -la                    # List files
find . -name "*.swift"    # Find Swift files
grep -r "pattern" Ourin/  # Search in source
```

## Git Operations
```bash
git status               # Check repository status
git diff                 # View changes
git add .                # Stage changes
git commit -m "message"  # Commit changes
```

## Notes
- No external package managers required
- All dependencies managed through Xcode project
- Use Xcode's built-in tools for debugging and profiling