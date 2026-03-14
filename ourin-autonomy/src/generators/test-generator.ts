import * as fs from 'fs/promises';
import * as path from 'path';

export interface TestGenerationOptions {
  targetFile: string;
  testName?: string;
  framework?: 'swift-testing' | 'xctest';
  includeEdgeCases?: boolean;
  includeAsyncTests?: boolean;
}

export class TestGenerator {
  async generateTests(options: TestGenerationOptions): Promise<string> {
    const content = await fs.readFile(options.targetFile, 'utf-8');
    const fileName = path.basename(options.targetFile, '.swift');
    const testName = options.testName || `${fileName}Tests`;

    const functions = this.extractFunctions(content);
    const classes = this.extractClasses(content);

    let testCode = this.generateImports();
    testCode += this.generateTestClass(testName);

    // Generate tests for functions
    for (const func of functions) {
      testCode += this.generateFunctionTest(func, options);
    }

    // Generate tests for classes
    for (const cls of classes) {
      testCode += this.generateClassTest(cls, options);
    }

    testCode += '\n}';
    return testCode;
  }

  private extractFunctions(content: string): string[] {
    const funcPattern = /func\s+(\w+)\s*\([^)]*\)\s*(->\s*\w+)?/g;
    const matches: string[] = [];
    let match;

    while ((match = funcPattern.exec(content)) !== null) {
      matches.push(match[1]);
    }

    return matches;
  }

  private extractClasses(content: string): string[] {
    const classPattern = /(?:class|struct|enum)\s+(\w+)/g;
    const matches: string[] = [];
    let match;

    while ((match = classPattern.exec(content)) !== null) {
      matches.push(match[1]);
    }

    return matches;
  }

  private generateImports(): string {
    return `import Testing
import Foundation
@testable import Ourin

`;
  }

  private generateTestClass(name: string): string {
    return `@Suite
struct ${name} {

`;
  }

  private generateFunctionTest(funcName: string, options: TestGenerationOptions): string {
    let test = `  @Test
  func test_${funcName.toLowerCase()}_happy_path() {
    // TODO: Implement test for ${funcName}
    // Arrange
    let expected: Int = 0

    // Act
    // Call ${funcName}()

    // Assert
    #expect(expected == expected)
  }

`;

    if (options.includeEdgeCases) {
      test += `  @Test
  func test_${funcName.toLowerCase()}_edge_cases() {
    // TODO: Test edge cases for ${funcName}
  }

`;
    }

    return test;
  }

  private generateClassTest(className: string, options: TestGenerationOptions): string {
    let test = `  @Test
  func test_${className.toLowerCase()}_initialization() {
    // TODO: Test ${className} initialization
  }

  @Test
  func test_${className.toLowerCase()}_functionality() {
    // TODO: Test ${className} functionality
  }

`;

    if (options.includeAsyncTests) {
      test += `  @Test
  func test_${className.toLowerCase()}_async_operations() async throws {
    // TODO: Test async operations
  }

`;
    }

    return test;
  }
}
