import { InputType, Field } from '@nestjs/graphql';

@InputType()
export class CreateSwapStreamInput {
  @Field()
  swapId: number;

  @Field()
  amountIn: string;

  @Field()
  amountOut: string;
}
