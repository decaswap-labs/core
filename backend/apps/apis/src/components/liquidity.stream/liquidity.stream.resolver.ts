import { Resolver, Query, Mutation, Args } from '@nestjs/graphql';

import { LiquidityStreamService } from './liquidity.stream.service';
import {
  LiquidityStream,
  LiquidityStreamType,
} from '@app/database/schemas/liquidity.stream.schema';
import { CreateLiquidityInput } from './dto/create.liquidity.input';

@Resolver(() => LiquidityStream)
export class LiquidityStreamResolver {
  constructor(private readonly liquidityService: LiquidityStreamService) {}

  @Query(() => [LiquidityStream])
  async liquidities() {
    return this.liquidityService.findAllLiquidities();
  }

  @Query(() => LiquidityStream)
  async liquidity(
    @Args('id') id: number,
    @Args('type', { type: () => LiquidityStreamType })
    type: LiquidityStreamType,
  ) {
    return this.liquidityService.findLiquidityByIdAndType(id, type);
  }

  @Mutation(() => LiquidityStream)
  async createLiquidity(
    @Args('data') data: CreateLiquidityInput, // Use the input type here
  ) {
    return this.liquidityService.createLiquidity(data);
  }
}
