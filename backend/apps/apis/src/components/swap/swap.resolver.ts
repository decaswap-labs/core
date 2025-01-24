import { Resolver, Query, Mutation, Args } from '@nestjs/graphql';

import { SwapService } from './swap.service';
import { Swap } from '@app/database/schemas/swap.schema';
import { SwapStream } from '@app/database/schemas/swap.stream.schema';
import { CreateSwapInput } from './dto/create.swap.input';
import { CreateSwapStreamInput } from './dto/create.swap.stream.input';

@Resolver(() => Swap)
export class SwapResolver {
  constructor(private readonly swapService: SwapService) {}

  @Query(() => [Swap])
  async swaps() {
    return this.swapService.findAllSwaps();
  }

  @Query(() => [SwapStream])
  async swapStreams() {
    return this.swapService.findAllSwapStreams();
  }

  @Query(() => Swap)
  async swapWithStreams(@Args('swapId') swapId: number) {
    return this.swapService.findSwapWithStreams(swapId);
  }

  @Mutation(() => Swap)
  async createSwap(@Args('data') data: CreateSwapInput) {
    return this.swapService.createSwap(data);
  }

  @Mutation(() => SwapStream)
  async createSwapStream(@Args('data') data: CreateSwapStreamInput) {
    return this.swapService.createSwapStream(data);
  }
}
