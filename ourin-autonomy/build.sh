#!/bin/bash

# Build script for ourin-autonomy

set -e

echo "🔨 Building ourin-autonomy..."

# Clean previous build
rm -rf dist

# Install dependencies
if [ ! -d "node_modules" ]; then
  echo "📦 Installing dependencies..."
  npm install
fi

# Build TypeScript
echo "⚙️  Compiling TypeScript..."
npm run build

# Make CLI executable
chmod +x dist/cli.js

echo "✅ Build complete!"
echo ""
echo "To use the CLI tool:"
echo "  ./dist/cli.js --help"
echo ""
echo "To use as MCP server:"
echo "  Already configured in .claude/mcp.json"
echo ""
echo "To use MCP tools, restart Claude Desktop or reload MCP servers"
