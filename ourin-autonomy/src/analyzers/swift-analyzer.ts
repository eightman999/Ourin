import * as fs from 'fs/promises';
import * as path from 'path';
import { glob } from 'glob';

export interface CodeIssue {
  file: string;
  line: number;
  column: number;
  severity: 'error' | 'warning' | 'info';
  message: string;
  rule: string;
  suggestion?: string;
}

export interface CodeMetrics {
  file: string;
  linesOfCode: number;
  complexity: number;
  functions: number;
  classes: number;
  issues: CodeIssue[];
}

export interface AnalysisResult {
  files: CodeMetrics[];
  summary: {
    totalFiles: number;
    totalLOC: number;
    avgComplexity: number;
    totalIssues: number;
    errors: number;
    warnings: number;
  };
  recommendations: string[];
}

export class SwiftAnalyzer {
  private projectRoot: string;

  constructor(projectRoot: string = process.cwd()) {
    this.projectRoot = projectRoot;
  }

  async analyze(pattern: string = '**/*.swift'): Promise<AnalysisResult> {
    const files = await glob(pattern, { cwd: this.projectRoot, absolute: true, nodir: true });
    const metrics: CodeMetrics[] = [];
    let totalLOC = 0;
    let totalComplexity = 0;
    let totalIssues = 0;
    let errors = 0;
    let warnings = 0;

    for (const file of files) {
      const content = await fs.readFile(file, 'utf-8');
      const metric = await this.analyzeFile(file, content);
      metrics.push(metric);

      totalLOC += metric.linesOfCode;
      totalComplexity += metric.complexity;
      totalIssues += metric.issues.length;
      errors += metric.issues.filter(i => i.severity === 'error').length;
      warnings += metric.issues.filter(i => i.severity === 'warning').length;
    }

    const summary = {
      totalFiles: files.length,
      totalLOC,
      avgComplexity: files.length > 0 ? totalComplexity / files.length : 0,
      totalIssues,
      errors,
      warnings
    };

    const recommendations = this.generateRecommendations(metrics, summary);

    return { files: metrics, summary, recommendations };
  }

  private async analyzeFile(filePath: string, content: string): Promise<CodeMetrics> {
    const issues: CodeIssue[] = [];

    // Basic complexity calculation (simplified)
    const complexity = this.calculateComplexity(content);

    // Count functions and classes
    const functions = (content.match(/func\s+\w+/g) || []).length;
    const classes = (content.match(/class\s+\w+/g) || []).length;

    // Check for common issues
    issues.push(...this.checkCodeQuality(filePath, content));

    return {
      file: filePath,
      linesOfCode: content.split('\n').length,
      complexity,
      functions,
      classes,
      issues
    };
  }

  private calculateComplexity(content: string): number {
    let complexity = 1; // Base complexity

    // Count control flow structures
    const patterns = [
      /\bif\b/g,
      /\belse\b/g,
      /\bfor\b/g,
      /\bwhile\b/g,
      /\bswitch\b/g,
      /\bcase\b/g,
      /\bguard\b/g,
      /\btry\b/g,
      /\bcatch\b/g
    ];

    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        complexity += matches.length;
      }
    }

    return complexity;
  }

  private checkCodeQuality(filePath: string, content: string): CodeIssue[] {
    const issues: CodeIssue[] = [];
    const lines = content.split('\n');

    lines.forEach((line, index) => {
      const lineNum = index + 1;

      // Check for long lines
      if (line.length > 120) {
        issues.push({
          file: filePath,
          line: lineNum,
          column: 0,
          severity: 'warning',
          message: 'Line exceeds 120 characters',
          rule: 'line-length',
          suggestion: 'Consider breaking this line into multiple lines'
        });
      }

      // Check for TODO comments
      if (line.includes('TODO') || line.includes('FIXME')) {
        issues.push({
          file: filePath,
          line: lineNum,
          column: 0,
          severity: 'info',
          message: 'Unresolved TODO or FIXME comment',
          rule: 'todo-comments',
          suggestion: 'Resolve the TODO or convert to an issue tracker'
        });
      }

      // Check for magic numbers
      const magicNumberPattern = /\b\d{2,}\b/g;
      const magicNumbers = line.match(magicNumberPattern);
      if (magicNumbers) {
        issues.push({
          file: filePath,
          line: lineNum,
          column: 0,
          severity: 'info',
          message: `Potential magic number(s): ${magicNumbers.join(', ')}`,
          rule: 'magic-numbers',
          suggestion: 'Consider using named constants'
        });
      }

      // Check for force unwrap
      if (line.includes('!') && !line.includes('!.')) {
        issues.push({
          file: filePath,
          line: lineNum,
          column: line.indexOf('!'),
          severity: 'warning',
          message: 'Force unwrap detected',
          rule: 'force-unwrap',
          suggestion: 'Consider using optional binding instead'
        });
      }
    });

    return issues;
  }

  private generateRecommendations(metrics: CodeMetrics[], summary: any): string[] {
    const recommendations: string[] = [];

    if (summary.avgComplexity > 15) {
      recommendations.push('High average complexity detected. Consider refactoring complex functions into smaller, more manageable units.');
    }

    if (summary.errors > 0) {
      recommendations.push(`Found ${summary.errors} errors that should be addressed immediately.`);
    }

    if (summary.warnings > 10) {
      recommendations.push(`Found ${summary.warnings} warnings. Review and resolve high-priority warnings.`);
    }

    const longFiles = metrics.filter(m => m.complexity > 20);
    if (longFiles.length > 0) {
      recommendations.push(`Found ${longFiles.length} files with high complexity. Consider breaking them down into smaller modules.`);
    }

    return recommendations;
  }
}
