import { Module } from '@nestjs/common';
import { ExecutionService } from './execution.service';
import { MyConfigModule } from '@app/utils/config/my.config.module';
import { PoolModule } from '../pool/pool.module';

@Module({
  imports: [MyConfigModule, PoolModule],
  providers: [ExecutionService],
  exports: [ExecutionService],
})
export class ExecutionModule {}
