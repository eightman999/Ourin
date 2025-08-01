# Task Completion Checklist

When completing development tasks in Ourin, follow this checklist:

## Code Quality Checks
- [ ] **Build successfully** - Run `xcodebuild -project Ourin.xcodeproj -scheme Ourin build`
- [ ] **Pass all tests** - Run `xcodebuild -project Ourin.xcodeproj -scheme Ourin test`
- [ ] **No compiler warnings** - Address any Swift compiler warnings
- [ ] **Memory management** - Ensure proper cleanup for FMO resources, plugins, etc.

## Code Review Points
- [ ] **Documentation** - Add Japanese comments for business logic, English for technical details
- [ ] **Error handling** - Proper `throws`/`try`/`catch` where needed
- [ ] **Resource cleanup** - Explicit cleanup methods called in `deinit` or appropriate lifecycle methods
- [ ] **Threading safety** - Consider thread safety for shared resources (FMO, plugins)

## Integration Testing
- [ ] **FMO functionality** - Test shared memory operations if modified
- [ ] **Plugin loading** - Verify plugin system still works if modified
- [ ] **SSTP protocol** - Test server responses if network code changed
- [ ] **System events** - Verify event monitoring if event system modified

## Final Steps
- [ ] **Manual testing** - Run the app and test the affected functionality
- [ ] **Performance check** - Ensure no significant performance regressions
- [ ] **Documentation update** - Update relevant docs/ files if protocols changed

## No Automatic Linting/Formatting
This project does not use automated linting or formatting tools. Code style should follow the conventions documented in the codebase and Swift best practices.