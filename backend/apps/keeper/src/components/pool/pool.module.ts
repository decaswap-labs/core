import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { Pool, PoolSchema } from '@app/database/schemas/pool.schema';
import { PoolService } from './pool.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Pool.name, schema: PoolSchema }]),
  ],
  providers: [PoolService],
  exports: [PoolService],
})
export class PoolModule {}
