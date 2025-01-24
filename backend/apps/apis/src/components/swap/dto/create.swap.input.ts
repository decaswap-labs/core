import { InputType, Field } from '@nestjs/graphql';

@InputType()
export class CreateSwapInput {
  @Field()
  swapId: number;

  @Field()
  pairId: string;

  @Field()
  swapAmount: string;

  @Field()
  executionPrice: string;

  @Field()
  user: string;

  @Field()
  typeOfOrder: number;
}
