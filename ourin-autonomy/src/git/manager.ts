import simpleGit, { SimpleGit } from 'simple-git';
import * as path from 'path';
import * as fs from 'fs/promises';

export interface GitBranch {
  name: string;
  isCurrent: boolean;
  commitHash: string;
}

export class GitManager {
  private git: SimpleGit;
  private projectRoot: string;

  constructor(projectRoot: string = process.cwd()) {
    this.projectRoot = projectRoot;
    this.git = simpleGit(projectRoot);
  }

  async getCurrentBranch(): Promise<string> {
    const status = await this.git.status();
    return status.current || 'main';
  }

  async getAllBranches(): Promise<GitBranch[]> {
    const branches = await this.git.branch();
    return branches.all.map(name => ({
      name,
      isCurrent: name === branches.current,
      commitHash: ''
    }));
  }

  async createBranch(branchName: string, baseBranch?: string): Promise<void> {
    if (baseBranch) {
      await this.git.checkoutBranch(branchName, `origin/${baseBranch}`);
    } else {
      await this.git.checkoutLocalBranch(branchName);
    }
  }

  async switchBranch(branchName: string): Promise<void> {
    await this.git.checkout(branchName);
  }

  async getChangedFiles(): Promise<string[]> {
    const status = await this.git.status();
    return [
      ...status.modified,
      ...status.created,
      ...status.deleted
    ];
  }

  async commit(message: string, files?: string[]): Promise<void> {
    if (files && files.length > 0) {
      await this.git.add(files);
    } else {
      await this.git.add('.');
    }
    await this.git.commit(message);
  }

  async createPullRequest(
    title: string,
    body: string,
    sourceBranch: string,
    targetBranch: string = 'main'
  ): Promise<void> {
    // PR creation requires GitHub CLI or API
    // For now, just show instructions
    console.log(`\n📝 Pull Request Instructions:`);
    console.log(`   Title: ${title}`);
    console.log(`   Source: ${sourceBranch}`);
    console.log(`   Target: ${targetBranch}`);
    console.log(`   Body:\n${body}\n`);
    console.log(`   Run: gh pr create --title "${title}" --body "${body}" --base ${targetBranch}\n`);
  }

  async getBranchInfo(branchName: string): Promise<{
    commits: any[];
    fileChanges: any[];
  }> {
    const log = await this.git.log({ from: `main`, to: branchName });
    return {
      commits: [...log.all],
      fileChanges: [] // Would need diff parsing
    };
  }

  async getDiff(filePath?: string): Promise<string> {
    if (filePath) {
      const diff = await this.git.diff([filePath]);
      return diff;
    }
    return await this.git.diff();
  }

  async revertFile(filePath: string): Promise<void> {
    await this.git.checkout([filePath]);
  }

  async stash(message?: string): Promise<string> {
    const result = await this.git.stash(['save', message || 'Autonomous agent changes']);
    return result;
  }

  async unstash(stashRef: string = 'stash@{0}'): Promise<void> {
    await this.git.stash(['apply', stashRef]);
  }
}
