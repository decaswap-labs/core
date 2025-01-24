import { InputType, Field } from '@nestjs/graphql';

@InputType()
export class CreatePoolInput {
  @Field()
  pairId: string;

  @Field()
  user: string;

  @Field()
  tokenAmount: string;

  @Field()
  dTokenAmount: string;

  @Field(() => Number, { defaultValue: 0 })
  outstandingTrades: number;
}
