import { Resolver, Query, Mutation, Args } from '@nestjs/graphql';

import { PoolService } from './pool.service';
import { Pool } from '@app/database/schemas/pool.schema';
import { CreatePoolInput } from './dto/create.pool.input';

@Resolver(() => Pool)
export class PoolResolver {
  constructor(private readonly poolService: PoolService) {}

  @Query(() => [Pool])
  async pools() {
    return this.poolService.findAllPools();
  }

  @Mutation(() => Pool)
  async createPool(@Args('data') data: CreatePoolInput) {
    return this.poolService.createPool(data);
  }
}
