import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { SwapService } from './swap.service';
import { SwapResolver } from './swap.resolver';
import { Swap, SwapSchema } from '@app/database/schemas/swap.schema';
import {
  SwapStream,
  SwapStreamSchema,
} from '@app/database/schemas/swap.stream.schema';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: Swap.name, schema: SwapSchema },
      { name: SwapStream.name, schema: SwapStreamSchema },
    ]),
  ],
  providers: [SwapService, SwapResolver],
})
export class SwapModule {}
