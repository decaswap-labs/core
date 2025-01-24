import { InputType, Field } from '@nestjs/graphql';

import { LiquidityStreamType } from '@app/database/schemas/liquidity.stream.schema';

@InputType()
export class CreateLiquidityInput {
  @Field()
  id: number;

  @Field()
  token: string;

  @Field()
  user: string;

  @Field()
  amount: string;

  @Field()
  streamCount: number;

  @Field()
  streamExecuted: number;

  @Field(() => LiquidityStreamType)
  type: LiquidityStreamType;
}
