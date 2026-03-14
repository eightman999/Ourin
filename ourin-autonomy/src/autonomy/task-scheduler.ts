import { Task } from './safety-level.js';

export class TaskScheduler {
  private tasks: Map<string, Task> = new Map();
  private executionQueue: string[] = [];
  private isProcessing: boolean = false;

  async scheduleTask(task: Task): Promise<void> {
    this.tasks.set(task.id, task);
    this.executionQueue.push(task.id);
    console.log(`📋 Task scheduled: ${task.id} (${task.type})`);
  }

  async processQueue(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    this.isProcessing = true;

    while (this.executionQueue.length > 0) {
      const taskId = this.executionQueue.shift();
      const task = this.tasks.get(taskId!);

      if (task) {
        await this.executeTask(task);
      }
    }

    this.isProcessing = false;
  }

  private async executeTask(task: Task): Promise<void> {
    try {
      task.status = 'executing';
      console.log(`\n⚙️  Executing task: ${task.id}`);

      await task.action();

      task.status = 'completed';
      console.log(`✅ Task completed: ${task.id}\n`);
    } catch (error) {
      task.status = 'failed';
      console.error(`❌ Task failed: ${task.id}`, error);
      throw error;
    }
  }

  getTask(taskId: string): Task | undefined {
    return this.tasks.get(taskId);
  }

  getAllTasks(): Task[] {
    return Array.from(this.tasks.values());
  }

  getPendingTasks(): Task[] {
    return Array.from(this.tasks.values()).filter(t => t.status === 'pending');
  }

  clearCompleted(): void {
    for (const [id, task] of this.tasks.entries()) {
      if (task.status === 'completed') {
        this.tasks.delete(id);
      }
    }
  }
}
