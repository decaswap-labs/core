import { Module } from '@nestjs/common';
import { SchedulerService } from './scheduler.service';
import { ExecutionModule } from '../execution/execution.module';
import { ScheduleModule } from '@nestjs/schedule';

@Module({
  imports: [ExecutionModule, ScheduleModule.forRoot({ cronJobs: true })],
  providers: [SchedulerService],
})
export class SchedulerModule {}
