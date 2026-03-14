import * as fs from 'fs/promises';
import * as path from 'path';

export interface RefactoringOption {
  file: string;
  type: string;
  description: string;
  originalCode: string;
  suggestedCode: string;
  lineStart: number;
  lineEnd: number;
  safety: 'safe' | 'caution' | 'unsafe';
}

export class RefactoringHelper {
  async analyzeRefactoringOpportunities(targetFile: string): Promise<RefactoringOption[]> {
    const content = await fs.readFile(targetFile, 'utf-8');
    const opportunities: RefactoringOption[] = [];

    // Check for duplicate code
    const duplicates = this.findDuplicateCode(content);
    opportunities.push(...duplicates);

    // Check for long functions
    const longFunctions = this.findLongFunctions(content);
    opportunities.push(...longFunctions);

    // Check for complex conditions
    const complexConditions = this.findComplexConditions(content);
    opportunities.push(...complexConditions);

    return opportunities;
  }

  private findDuplicateCode(content: string): RefactoringOption[] {
    const opportunities: RefactoringOption[] = [];
    const lines = content.split('\n');
    const codeBlocks: Map<string, number[]> = new Map();

    // Find repeated code blocks (simplified)
    for (let i = 0; i < lines.length - 2; i++) {
      const block = lines.slice(i, i + 3).join('\n').trim();
      if (block.length > 50 && !block.startsWith('//') && !block.startsWith('import')) {
        if (codeBlocks.has(block)) {
          const positions = codeBlocks.get(block)!;
          if (positions.length === 1) {
            opportunities.push({
              file: '', // Will be filled by caller
              type: 'extract-method',
              description: 'Duplicate code detected. Consider extracting to a method.',
              originalCode: block,
              suggestedCode: `private func extractedMethod() {\n  ${block.split('\n').map(l => '  ' + l).join('\n')}\n}`,
              lineStart: i + 1,
              lineEnd: i + 3,
              safety: 'safe'
            });
          }
          positions.push(i + 1);
        } else {
          codeBlocks.set(block, [i + 1]);
        }
      }
    }

    return opportunities;
  }

  private findLongFunctions(content: string): RefactoringOption[] {
    const opportunities: RefactoringOption[] = [];
    const lines = content.split('\n');

    let currentFunction: { name: string; startLine: number; lines: string[] } | null = null;
    let braceCount = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Track function definition
      const funcMatch = line.match(/func\s+(\w+)\s*\(/);
      if (funcMatch && !currentFunction) {
        currentFunction = { name: funcMatch[1], startLine: i + 1, lines: [] };
      }

      // Count braces
      const openBraces = (line.match(/\{/g) || []).length;
      const closeBraces = (line.match(/\}/g) || []).length;
      braceCount += openBraces - closeBraces;

      if (currentFunction) {
        currentFunction.lines.push(line);

        // Function end
        if (braceCount === 0 && currentFunction.lines.length > 30) {
          opportunities.push({
            file: '',
            type: 'extract-function',
            description: `Function '${currentFunction.name}' is too long (${currentFunction.lines.length} lines). Consider splitting into smaller functions.`,
            originalCode: currentFunction.lines.join('\n'),
            suggestedCode: `// TODO: Split ${currentFunction.name} into smaller, more focused functions`,
            lineStart: currentFunction.startLine,
            lineEnd: i + 1,
            safety: 'caution'
          });
          currentFunction = null;
        } else if (braceCount === 0) {
          currentFunction = null;
        }
      }
    }

    return opportunities;
  }

  private findComplexConditions(content: string): RefactoringOption[] {
    const opportunities: RefactoringOption[] = [];
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Check for complex boolean expressions
      const andCount = (line.match(/&&/g) || []).length;
      const orCount = (line.match(/\|\|/g) || []).length;
      const totalComplexity = andCount + orCount;

      if (totalComplexity >= 4) {
        const match = line.match(/\s+if\s+(.+)/);
        if (match) {
          opportunities.push({
            file: '',
            type: 'extract-variable',
            description: 'Complex boolean expression. Consider extracting to named variables or methods.',
            originalCode: line.trim(),
            suggestedCode: `let condition = /* complex condition */\nif condition {`,
            lineStart: i + 1,
            lineEnd: i + 1,
            safety: 'safe'
          });
        }
      }
    }

    return opportunities;
  }

  async applyRefactoring(option: RefactoringOption): Promise<string> {
    const content = await fs.readFile(option.file, 'utf-8');
    const lines = content.split('\n');

    // Replace the code
    const before = lines.slice(0, option.lineStart - 1);
    const after = lines.slice(option.lineEnd);
    const suggestedLines = option.suggestedCode.split('\n');

    const newContent = [...before, ...suggestedLines, ...after].join('\n');
    return newContent;
  }

  async formatSwiftCode(content: string): Promise<string> {
    // Basic formatting (simplified - in production, use swiftformat)
    let formatted = content;

    // Remove trailing whitespace
    formatted = formatted.replace(/[ \t]+$/gm, '');

    // Ensure single blank line between functions
    formatted = formatted.replace(/\n{3,}/g, '\n\n');

    // Remove blank lines at end of file
    formatted = formatted.replace(/\n+$/, '\n');

    return formatted;
  }
}
