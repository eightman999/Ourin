export interface SafetyLevel {
  level: 1 | 2 | 3 | 4 | 5;
  name: string;
  description: string;
  canAutoExecute: boolean;
  requiresApproval: boolean;
  allowedActions: string[];
}

export const SAFETY_LEVELS: SafetyLevel[] = [
  {
    level: 1,
    name: 'Read-only Analysis',
    description: 'Code analysis, documentation generation, metrics collection',
    canAutoExecute: true,
    requiresApproval: false,
    allowedActions: ['analyze', 'document', 'measure', 'search']
  },
  {
    level: 2,
    name: 'Safe Auto-Execution',
    description: 'Test generation, documentation updates, safe refactoring',
    canAutoExecute: true,
    requiresApproval: false,
    allowedActions: ['test', 'document', 'refactor_safe', 'format']
  },
  {
    level: 3,
    name: 'Semi-Autonomous',
    description: 'Bug fixes, feature implementation with review',
    canAutoExecute: false,
    requiresApproval: true,
    allowedActions: ['fix_bug', 'implement_feature', 'refactor_medium']
  },
  {
    level: 4,
    name: 'Supervised Autonomy',
    description: 'Major refactoring, architecture changes with strict review',
    canAutoExecute: false,
    requiresApproval: true,
    allowedActions: ['refactor_major', 'architecture_change', 'api_change']
  },
  {
    level: 5,
    name: 'Critical Operations',
    description: 'Breaking changes, data migration, destructive operations',
    canAutoExecute: false,
    requiresApproval: true,
    allowedActions: ['breaking_change', 'migration', 'destructive']
  }
];

export interface Task {
  id: string;
  type: string;
  safetyLevel: number;
  description: string;
  action: () => Promise<void>;
  estimatedRisk: 'low' | 'medium' | 'high' | 'critical';
  dependencies?: string[];
  createdAt: Date;
  status: 'pending' | 'approved' | 'rejected' | 'executing' | 'completed' | 'failed';
}

export class SafetyLevelManager {
  private currentLevel: number = 1;
  private approvalCallbacks: Map<string, (approved: boolean) => void> = new Map();

  setCurrentLevel(level: number) {
    if (level < 1 || level > 5) {
      throw new Error('Safety level must be between 1 and 5');
    }
    this.currentLevel = level;
  }

  getCurrentLevel(): number {
    return this.currentLevel;
  }

  getSafetyLevel(level: number): SafetyLevel {
    return SAFETY_LEVELS[level - 1];
  }

  canExecuteAction(action: string): boolean {
    const level = this.getSafetyLevel(this.currentLevel);
    return level.allowedActions.includes(action);
  }

  canAutoExecute(safetyLevel: number): boolean {
    if (safetyLevel > this.currentLevel) {
      return false;
    }
    const level = this.getSafetyLevel(safetyLevel);
    return level.canAutoExecute && safetyLevel <= this.currentLevel;
  }

  requiresApproval(safetyLevel: number): boolean {
    const level = this.getSafetyLevel(safetyLevel);
    return level.requiresApproval || safetyLevel > this.currentLevel;
  }

  async requestApproval(taskId: string, task: Task): Promise<boolean> {
    return new Promise((resolve) => {
      this.approvalCallbacks.set(taskId, resolve);
      console.log(`\n🔒 Approval Required for Task: ${task.id}`);
      console.log(`   Type: ${task.type}`);
      console.log(`   Safety Level: ${task.safetyLevel}`);
      console.log(`   Risk: ${task.estimatedRisk}`);
      console.log(`   Description: ${task.description}`);
      console.log(`   Action: ${this.getSafetyLevel(task.safetyLevel).name}`);
      console.log(`\n⚠️  This task requires manual approval.`);
      console.log(`   To approve: ourin-autonomy approve ${taskId}`);
      console.log(`   To reject: ourin-autonomy reject ${taskId}\n`);
    });
  }

  handleApproval(taskId: string, approved: boolean) {
    const callback = this.approvalCallbacks.get(taskId);
    if (callback) {
      callback(approved);
      this.approvalCallbacks.delete(taskId);
    }
  }
}
