import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { Pool, PoolSchema } from '@app/database/schemas/pool.schema';
import { PoolService } from './pool.service';
import { PoolResolver } from './pool.resolver';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Pool.name, schema: PoolSchema }]),
  ],
  providers: [PoolService, PoolResolver],
  exports: [PoolService],
})
export class PoolModule {}
