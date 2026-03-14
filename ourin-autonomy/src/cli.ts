#!/usr/bin/env node

import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import inquirer from 'inquirer';
import { SwiftAnalyzer } from './analyzers/swift-analyzer.js';
import { TestGenerator } from './generators/test-generator.js';
import { DocGenerator } from './generators/doc-generator.js';
import { RefactoringHelper } from './refactoring/safe-refactor.js';
import { SafetyLevelManager, Task } from './autonomy/safety-level.js';
import { TaskScheduler } from './autonomy/task-scheduler.js';
import { GitManager } from './git/manager.js';
import * as fs from 'fs/promises';
import * as path from 'path';

const program = new Command();
const spinner = ora();

// Initialize managers
const analyzer = new SwiftAnalyzer(process.cwd());
const testGen = new TestGenerator();
const docGen = new DocGenerator();
const refactor = new RefactoringHelper();
const safetyManager = new SafetyLevelManager();
const taskScheduler = new TaskScheduler();
const gitManager = new GitManager();

program
  .name('ourin-autonomy')
  .description('Autonomous AI agent tool for improving Ourin project')
  .version('1.0.0');

// Set safety level
program
  .command('safety')
  .description('Set or view current safety level')
  .argument('[level]', 'Safety level (1-5)', null)
  .action(async (level) => {
    if (level) {
      const levelNum = parseInt(level);
      if (levelNum < 1 || levelNum > 5) {
        console.error(chalk.red('Error: Safety level must be between 1 and 5'));
        process.exit(1);
      }
      safetyManager.setCurrentLevel(levelNum);
      const levelInfo = safetyManager.getSafetyLevel(levelNum);
      console.log(chalk.green(`✓ Safety level set to ${levelNum}: ${levelInfo.name}`));
      console.log(chalk.gray(`  ${levelInfo.description}`));
    } else {
      const current = safetyManager.getCurrentLevel();
      const levelInfo = safetyManager.getSafetyLevel(current);
      console.log(chalk.blue(`Current Safety Level: ${current} - ${levelInfo.name}`));
      console.log(chalk.gray(levelInfo.description));
    }
  });

// Analyze code
program
  .command('analyze')
  .description('Analyze Swift code for quality and metrics')
  .option('-p, --pattern <pattern>', 'Glob pattern for files', '**/*.swift')
  .option('-o, --output <file>', 'Output file for report')
  .action(async (options) => {
    spinner.start('Analyzing code...');
    try {
      const analysis = await analyzer.analyze(options.pattern);
      spinner.succeed('Analysis complete');

      console.log('\n' + chalk.bold('Analysis Summary:'));
      console.log(`  Total Files: ${chalk.cyan(analysis.summary.totalFiles)}`);
      console.log(`  Total LOC: ${chalk.cyan(analysis.summary.totalLOC)}`);
      console.log(`  Avg Complexity: ${chalk.cyan(analysis.summary.avgComplexity.toFixed(2))}`);
      console.log(`  Total Issues: ${chalk.yellow(analysis.summary.totalIssues)}`);
      console.log(`    Errors: ${chalk.red(analysis.summary.errors)}`);
      console.log(`    Warnings: ${chalk.yellow(analysis.summary.warnings)}`);

      if (analysis.recommendations.length > 0) {
        console.log('\n' + chalk.bold('Recommendations:'));
        analysis.recommendations.forEach((rec, i) => {
          console.log(`  ${i + 1}. ${rec}`);
        });
      }

      if (options.output) {
        const report = await docGen.generateMarkdownReport(analysis);
        await fs.writeFile(options.output, report, 'utf-8');
        console.log(chalk.green(`\n✓ Report saved to ${options.output}`));
      }
    } catch (error) {
      spinner.fail('Analysis failed');
      console.error(error);
      process.exit(1);
    }
  });

// Generate tests
program
  .command('test-gen')
  .description('Generate unit tests for Swift files')
  .argument('<file>', 'Swift file to generate tests for')
  .option('-o, --output <file>', 'Output file for tests')
  .option('-e, --edge-cases', 'Include edge case tests')
  .action(async (file, options) => {
    spinner.start('Generating tests...');
    try {
      const tests = await testGen.generateTests({
        targetFile: file,
        includeEdgeCases: options.edgeCases,
      });
      spinner.succeed('Tests generated');

      if (options.output) {
        await fs.writeFile(options.output, tests, 'utf-8');
        console.log(chalk.green(`✓ Tests saved to ${options.output}`));
      } else {
        console.log('\n' + tests);
      }
    } catch (error) {
      spinner.fail('Test generation failed');
      console.error(error);
      process.exit(1);
    }
  });

// Generate documentation
program
  .command('doc-gen')
  .description('Generate documentation for Swift files')
  .argument('<file>', 'Swift file to document')
  .option('-o, --output <file>', 'Output file for documentation')
  .option('-f, --format <format>', 'Output format (markdown|html)', 'markdown')
  .option('-e, --examples', 'Include usage examples')
  .action(async (file, options) => {
    spinner.start('Generating documentation...');
    try {
      const docs = await docGen.generateDocumentation({
        targetFile: file,
        format: options.format,
        includeExamples: options.examples,
      });
      spinner.succeed('Documentation generated');

      if (options.output) {
        await fs.writeFile(options.output, docs, 'utf-8');
        console.log(chalk.green(`✓ Documentation saved to ${options.output}`));
      } else {
        console.log('\n' + docs);
      }
    } catch (error) {
      spinner.fail('Documentation generation failed');
      console.error(error);
      process.exit(1);
    }
  });

// Analyze refactoring opportunities
program
  .command('refactor-analyze')
  .description('Analyze code for refactoring opportunities')
  .argument('<file>', 'Swift file to analyze')
  .action(async (file) => {
    spinner.start('Analyzing refactoring opportunities...');
    try {
      const opportunities = await refactor.analyzeRefactoringOpportunities(file);
      spinner.succeed('Analysis complete');

      if (opportunities.length === 0) {
        console.log(chalk.green('✓ No refactoring opportunities found'));
      } else {
        console.log('\n' + chalk.bold('Refactoring Opportunities:'));
        opportunities.forEach((opp, i) => {
          const safetyIcon = opp.safety === 'safe' ? chalk.green('✓') : opp.safety === 'caution' ? chalk.yellow('⚠') : chalk.red('✗');
          console.log(`\n${i + 1}. ${safetyIcon} ${opp.type}`);
          console.log(`   ${chalk.gray(opp.description)}`);
          console.log(`   Line: ${opp.lineStart}-${opp.lineEnd}`);
        });
      }
    } catch (error) {
      spinner.fail('Analysis failed');
      console.error(error);
      process.exit(1);
    }
  });

// Task approval
program
  .command('approve')
  .description('Approve a pending task')
  .argument('<taskId>', 'Task ID to approve')
  .action(async (taskId) => {
    const task = taskScheduler.getTask(taskId);
    if (!task) {
      console.error(chalk.red(`Error: Task ${taskId} not found`));
      process.exit(1);
    }

    if (task.status !== 'pending') {
      console.error(chalk.red(`Error: Task ${taskId} is not pending (status: ${task.status})`));
      process.exit(1);
    }

    console.log('\n' + chalk.bold('Task Details:'));
    console.log(`  ID: ${task.id}`);
    console.log(`  Type: ${task.type}`);
    console.log(`  Safety Level: ${task.safetyLevel}`);
    console.log(`  Risk: ${task.estimatedRisk}`);
    console.log(`  Description: ${task.description}`);

    const { confirm } = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'confirm',
        message: 'Do you want to approve and execute this task?',
        default: false,
      },
    ]);

    if (confirm) {
      spinner.start('Executing task...');
      try {
        await task.action();
        task.status = 'completed';
        spinner.succeed('Task completed');
      } catch (error) {
        task.status = 'failed';
        spinner.fail('Task failed');
        console.error(error);
        process.exit(1);
      }
    } else {
      task.status = 'rejected';
      console.log(chalk.yellow('Task rejected'));
    }
  });

// List pending tasks
program
  .command('tasks')
  .description('List all pending tasks')
  .action(async () => {
    const tasks = taskScheduler.getPendingTasks();

    if (tasks.length === 0) {
      console.log(chalk.green('✓ No pending tasks'));
    } else {
      console.log('\n' + chalk.bold(`Pending Tasks (${tasks.length}):`));
      tasks.forEach((task) => {
        const riskColor = task.estimatedRisk === 'low' ? chalk.green : task.estimatedRisk === 'medium' ? chalk.yellow : chalk.red;
        console.log(`\n  ${chalk.cyan(task.id)}`);
        console.log(`    Type: ${task.type}`);
        console.log(`    Safety Level: ${task.safetyLevel}`);
        console.log(`    Risk: ${riskColor(task.estimatedRisk)}`);
        console.log(`    Description: ${task.description}`);
      });
    }
  });

// Git integration
program
  .command('branch')
  .description('Create a new branch for autonomous work')
  .argument('<name>', 'Branch name')
  .option('-b, --base <branch>', 'Base branch', 'main')
  .action(async (name, options) => {
    spinner.start(`Creating branch ${name}...`);
    try {
      await gitManager.createBranch(name, options.base);
      spinner.succeed(`Branch ${name} created from ${options.base}`);
    } catch (error) {
      spinner.fail('Branch creation failed');
      console.error(error);
      process.exit(1);
    }
  });

program
  .command('commit')
  .description('Commit autonomous agent changes')
  .argument('<message>', 'Commit message')
  .option('-a, --all', 'Stage all changes')
  .action(async (message, options) => {
    spinner.start('Committing changes...');
    try {
      await gitManager.commit(message, options.all ? undefined : []);
      spinner.succeed('Changes committed');
    } catch (error) {
      spinner.fail('Commit failed');
      console.error(error);
      process.exit(1);
    }
  });

// Auto mode - runs analysis and suggestions
program
  .command('auto')
  .description('Run autonomous improvement workflow')
  .action(async () => {
    console.log(chalk.bold('\n🤖 Ourin Autonomy Tool - Auto Mode\n'));

    // Step 1: Analyze code
    spinner.start('Step 1/3: Analyzing code...');
    const analysis = await analyzer.analyze('**/*.swift');
    spinner.succeed('Code analyzed');

    console.log(`  Found ${analysis.summary.totalIssues} issues (${analysis.summary.errors} errors, ${analysis.summary.warnings} warnings)`);

    // Step 2: Generate recommendations
    spinner.start('Step 2/3: Generating recommendations...');
    const tasks: Task[] = [];

    if (analysis.summary.errors > 0) {
      tasks.push({
        id: `fix_errors_${Date.now()}`,
        type: 'fix_bug',
        safetyLevel: 3,
        description: 'Fix reported errors in codebase',
        action: async () => {
          console.log('Manual fix required for errors');
        },
        estimatedRisk: 'medium',
        createdAt: new Date(),
        status: 'pending',
      });
    }

    spinner.succeed('Recommendations generated');

    // Step 3: Offer to execute tasks
    if (tasks.length > 0) {
      console.log('\n' + chalk.bold('Recommended Actions:'));
      tasks.forEach((task, i) => {
        console.log(`  ${i + 1}. ${task.description} (Safety Level: ${task.safetyLevel})`);
      });

      const { autoExecute } = await inquirer.prompt([
        {
          type: 'confirm',
          name: 'autoExecute',
          message: 'Do you want to create tasks for these actions?',
          default: false,
        },
      ]);

      if (autoExecute) {
        for (const task of tasks) {
          await taskScheduler.scheduleTask(task);
        }
        console.log(chalk.green(`✓ ${tasks.length} tasks created`));
      }
    } else {
      console.log(chalk.green('\n✓ No actions required'));
    }

    console.log('\n' + chalk.bold('Summary:'));
    console.log(`  Files analyzed: ${analysis.summary.totalFiles}`);
    console.log(`  Lines of code: ${analysis.summary.totalLOC}`);
    console.log(`  Issues found: ${analysis.summary.totalIssues}`);
    console.log(`  Tasks created: ${tasks.length}`);
  });

// Show safety levels
program
  .command('safety-levels')
  .description('Show all available safety levels')
  .action(() => {
    console.log('\n' + chalk.bold('Safety Levels:'));
    for (let i = 1; i <= 5; i++) {
      const level = safetyManager.getSafetyLevel(i);
      const icon = level.canAutoExecute ? chalk.green('🟢') : level.requiresApproval ? chalk.yellow('🟡') : chalk.red('🔴');
      console.log(`\n${icon} Level ${i}: ${level.name}`);
      console.log(`   ${level.description}`);
      console.log(`   Auto-execute: ${level.canAutoExecute ? 'Yes' : 'No'}`);
      console.log(`   Requires approval: ${level.requiresApproval ? 'Yes' : 'No'}`);
    }
  });

program.parse();
