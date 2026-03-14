#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { SwiftAnalyzer } from './analyzers/swift-analyzer.js';
import { TestGenerator } from './generators/test-generator.js';
import { DocGenerator } from './generators/doc-generator.js';
import { RefactoringHelper } from './refactoring/safe-refactor.js';
import { SafetyLevelManager, Task } from './autonomy/safety-level.js';
import { TaskScheduler } from './autonomy/task-scheduler.js';
import { GitManager } from './git/manager.js';
import * as fs from 'fs/promises';
import * as path from 'path';

const server = new Server(
  {
    name: 'ourin-autonomy',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Initialize managers
const analyzer = new SwiftAnalyzer(process.cwd());
const testGen = new TestGenerator();
const docGen = new DocGenerator();
const refactor = new RefactoringHelper();
const safetyManager = new SafetyLevelManager();
const taskScheduler = new TaskScheduler();
const gitManager = new GitManager();

// Task ID counter
let taskIdCounter = 0;

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'set_safety_level',
        description: 'Set the current safety level (1-5) for autonomous operations',
        inputSchema: {
          type: 'object',
          properties: {
            level: {
              type: 'number',
              description: 'Safety level (1=Read-only, 2=Safe Auto, 3=Semi-Autonomous, 4=Supervised, 5=Critical)',
              minimum: 1,
              maximum: 5,
            },
          },
          required: ['level'],
        },
      },
      {
        name: 'analyze_code',
        description: 'Analyze Swift code for quality issues, complexity, and metrics',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: {
              type: 'string',
              description: 'Glob pattern for files to analyze (default: **/*.swift)',
            },
          },
          required: [],
        },
      },
      {
        name: 'generate_tests',
        description: 'Generate unit tests for Swift files',
        inputSchema: {
          type: 'object',
          properties: {
            target_file: {
              type: 'string',
              description: 'Path to the Swift file to generate tests for',
            },
            test_name: {
              type: 'string',
              description: 'Optional name for the test suite',
            },
            include_edge_cases: {
              type: 'boolean',
              description: 'Include edge case tests',
            },
          },
          required: ['target_file'],
        },
      },
      {
        name: 'generate_documentation',
        description: 'Generate documentation for Swift files',
        inputSchema: {
          type: 'object',
          properties: {
            target_file: {
              type: 'string',
              description: 'Path to the Swift file to document',
            },
            format: {
              type: 'string',
              enum: ['markdown', 'html'],
              description: 'Output format',
            },
            include_examples: {
              type: 'boolean',
              description: 'Include usage examples',
            },
          },
          required: ['target_file'],
        },
      },
      {
        name: 'analyze_refactoring',
        description: 'Analyze code for refactoring opportunities',
        inputSchema: {
          type: 'object',
          properties: {
            target_file: {
              type: 'string',
              description: 'Path to the Swift file to analyze',
            },
          },
          required: ['target_file'],
        },
      },
      {
        name: 'apply_refactoring',
        description: 'Apply a safe refactoring to a file',
        inputSchema: {
          type: 'object',
          properties: {
            target_file: {
              type: 'string',
              description: 'Path to the Swift file',
            },
            refactoring_type: {
              type: 'string',
              description: 'Type of refactoring to apply',
            },
          },
          required: ['target_file'],
        },
      },
      {
        name: 'generate_analysis_report',
        description: 'Generate a comprehensive analysis report in Markdown',
        inputSchema: {
          type: 'object',
          properties: {
            output_file: {
              type: 'string',
              description: 'Output file path for the report',
            },
          },
          required: [],
        },
      },
      {
        name: 'get_safety_status',
        description: 'Get current safety level and status',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
      {
        name: 'list_pending_tasks',
        description: 'List all pending autonomous tasks',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'set_safety_level': {
        const level = args?.level as number;
        if (level < 1 || level > 5) {
          throw new Error('Safety level must be between 1 and 5');
        }
        safetyManager.setCurrentLevel(level);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                message: `Safety level set to ${level}: ${safetyManager.getSafetyLevel(level).name}`,
                level,
                description: safetyManager.getSafetyLevel(level).description,
              }, null, 2),
            },
          ],
        };
      }

      case 'analyze_code': {
        const pattern = args?.pattern as string || '**/*.swift';
        const analysis = await analyzer.analyze(pattern);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(analysis, null, 2),
            },
          ],
        };
      }

      case 'generate_tests': {
        const targetFile = args?.target_file as string;
        const testName = args?.test_name as string;
        const includeEdgeCases = args?.include_edge_cases as boolean;

        if (!targetFile) {
          throw new Error('target_file is required');
        }

        const tests = await testGen.generateTests({
          targetFile: targetFile,
          testName: testName,
          framework: 'swift-testing',
          includeEdgeCases: includeEdgeCases ?? true,
        });

        return {
          content: [
            {
              type: 'text',
              text: tests,
            },
          ],
        };
      }

      case 'generate_documentation': {
        const targetFile = args?.target_file as string;
        const format = (args?.format as string) || 'markdown';
        const includeExamples = args?.include_examples as boolean;

        if (!targetFile) {
          throw new Error('target_file is required');
        }

        const docs = await docGen.generateDocumentation({
          targetFile: targetFile,
          format: format as any,
          includeExamples: includeExamples ?? false,
          includeTypeSignatures: true,
        });

        return {
          content: [
            {
              type: 'text',
              text: docs,
            },
          ],
        };
      }

      case 'analyze_refactoring': {
        const targetFile = args?.target_file as string;
        if (!targetFile) {
          throw new Error('target_file is required');
        }

        const opportunities = await refactor.analyzeRefactoringOpportunities(targetFile);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(opportunities, null, 2),
            },
          ],
        };
      }

      case 'apply_refactoring': {
        const targetFile = args?.target_file as string;
        const refactoringType = args?.refactoring_type as string;

        if (!targetFile) {
          throw new Error('target_file is required');
        }

        // Check if operation is allowed at current safety level
        if (!safetyManager.canExecuteAction('refactor_safe')) {
          throw new Error(`Refactoring not allowed at safety level ${safetyManager.getCurrentLevel()}`);
        }

        const opportunities = await refactor.analyzeRefactoringOpportunities(targetFile);
        const opportunity = opportunities.find(o => o.type === refactoringType);

        if (!opportunity) {
          throw new Error(`Refactoring opportunity of type '${refactoringType}' not found`);
        }

        // Apply refactoring if safe enough or auto-approved
        if (safetyManager.canAutoExecute(2)) {
          const newContent = await refactor.applyRefactoring(opportunity);
          await fs.writeFile(targetFile, newContent, 'utf-8');
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  message: 'Refactoring applied successfully',
                  file: targetFile,
                  type: refactoringType,
                }, null, 2),
              },
            ],
          };
        } else {
          // Requires approval
          const taskId = `refactor_${Date.now()}`;
          const task: Task = {
            id: taskId,
            type: refactoringType,
            safetyLevel: 2,
            description: `Apply ${refactoringType} to ${targetFile}`,
            action: async () => {
              const newContent = await refactor.applyRefactoring(opportunity);
              await fs.writeFile(targetFile, newContent, 'utf-8');
            },
            estimatedRisk: 'low',
            createdAt: new Date(),
            status: 'pending',
          };
          await taskScheduler.scheduleTask(task);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  message: 'Refactoring requires approval',
                  taskId,
                  safetyLevel: 2,
                  description: task.description,
                  action: 'Use CLI to approve: ourin-autonomy approve ' + taskId,
                }, null, 2),
              },
            ],
          };
        }
      }

      case 'generate_analysis_report': {
        const outputFile = args?.output_file as string;
        const analysis = await analyzer.analyze('**/*.swift');
        const report = await docGen.generateMarkdownReport(analysis);

        if (outputFile) {
          await fs.writeFile(outputFile, report, 'utf-8');
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  message: 'Report generated',
                  file: outputFile,
                }, null, 2),
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: report,
            },
          ],
        };
      }

      case 'get_safety_status': {
        const currentLevel = safetyManager.getCurrentLevel();
        const levelInfo = safetyManager.getSafetyLevel(currentLevel);
        const pendingTasks = taskScheduler.getPendingTasks();

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                currentLevel,
                levelInfo,
                pendingTasks: pendingTasks.length,
                canAutoExecute: levelInfo.canAutoExecute,
                requiresApproval: levelInfo.requiresApproval,
              }, null, 2),
            },
          ],
        };
      }

      case 'list_pending_tasks': {
        const tasks = taskScheduler.getAllTasks();
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(tasks, null, 2),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            error: error instanceof Error ? error.message : 'Unknown error',
          }),
        },
      ],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('ourin-autonomy MCP server started');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
