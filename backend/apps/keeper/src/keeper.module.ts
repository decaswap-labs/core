import { Module } from '@nestjs/common';
import { KeeperController } from './keeper.controller';
import { KeeperService } from './keeper.service';
import { DatabaseModule } from '@app/database';
import { ConfigModule } from '@nestjs/config';
import { ExecutionModule } from './components/execution/execution.module';
import { SchedulerModule } from './components/scheduler/scheduler.module';
import { MonitoringModule } from './components/monitoring/monitoring.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    DatabaseModule,
    ExecutionModule,
    SchedulerModule,
    MonitoringModule,
  ],
  controllers: [KeeperController],
  providers: [KeeperService],
})
export class KeeperModule {}
