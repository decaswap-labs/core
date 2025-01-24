import { Injectable, Logger } from '@nestjs/common';
import { ExecutionService } from '../execution/execution.service';
import { Cron, CronExpression } from '@nestjs/schedule';

@Injectable()
export class SchedulerService {
  private readonly logger = new Logger(SchedulerService.name);
  private isCronRunning = false;

  constructor(private readonly executionService: ExecutionService) {}

  @Cron(CronExpression.EVERY_MINUTE) // Runs every minute
  async handleCron() {
    if (this.isCronRunning) {
      this.logger.warn(
        'Cron job skipped: Previous execution still in progress.',
      );
      return;
    }

    this.isCronRunning = true;
    this.logger.log('Cron job started.');

    try {
      await this.executionService.callMaintenance();
      this.logger.log('Cron job completed successfully.');
    } catch (error) {
      this.logger.error('Error during cron job execution:', error);
    } finally {
      this.isCronRunning = false;
      this.logger.log('Cron job status reset.');
    }
  }
}
