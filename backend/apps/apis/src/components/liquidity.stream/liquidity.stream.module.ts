import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import {
  LiquidityStream,
  LiquidityStreamSchema,
} from '@app/database/schemas/liquidity.stream.schema';
import { LiquidityStreamService } from './liquidity.stream.service';
import { LiquidityStreamResolver } from './liquidity.stream.resolver';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: LiquidityStream.name, schema: LiquidityStreamSchema },
    ]),
  ],
  providers: [LiquidityStreamService, LiquidityStreamResolver],
  exports: [LiquidityStreamService],
})
export class LiquidityStreamModule {}
