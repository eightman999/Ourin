# Code Style and Conventions

## Swift Style Guidelines

### Class/Struct Declarations
- Use `final class` for classes that shouldn't be inherited
- Prefer `struct` for value types
- Use descriptive names following Swift naming conventions

### Documentation
- **Japanese comments** for internal documentation and business logic
- **English** for public APIs and technical implementation details
- Use `///` for public API documentation
- Use `//` for internal comments

### Code Organization
- One primary type per file
- Group related functionality in extensions
- Use `// MARK:` for section organization

### Error Handling
- Use `throws` for recoverable errors
- Custom error types when appropriate
- Proper resource cleanup in `deinit` or explicit cleanup methods

### Memory Management
- Explicit cleanup methods for system resources (FMO, plugins)
- Use `weak` references to avoid retain cycles
- RAII pattern where applicable

## Naming Conventions
- Classes: `PascalCase` (e.g., `FmoManager`, `SSTPDispatcher`)
- Methods/Properties: `camelCase`
- Constants: `camelCase` for local, `PascalCase` for static
- Enums: `PascalCase` with `camelCase` cases

## Architecture Patterns
- **Manager/Coordinator** pattern for system components
- **Bridge** pattern for C integration
- **Dispatcher** pattern for request routing
- **Registry** pattern for plugin management