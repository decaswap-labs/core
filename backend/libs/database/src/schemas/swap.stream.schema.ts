import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { ObjectType, Field } from '@nestjs/graphql';
import { Document } from 'mongoose';

@Schema()
@ObjectType()
export class SwapStream {
  @Prop({ required: true })
  @Field()
  swapId: number;

  @Prop({ required: true })
  @Field()
  amountIn: string;

  @Prop({ required: true })
  @Field()
  amountOut: string;
}

export type SwapStreamDocument = SwapStream & Document;
export const SwapStreamSchema = SchemaFactory.createForClass(SwapStream);
