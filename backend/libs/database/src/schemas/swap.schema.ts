import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { ObjectType, Field } from '@nestjs/graphql';
import { Document } from 'mongoose';

@Schema()
@ObjectType()
export class Swap {
  @Prop({ required: true })
  @Field()
  swapId: number;

  @Prop({ required: true })
  @Field()
  pairId: string;

  @Prop({ required: true })
  @Field()
  swapAmount: string;

  @Prop({ required: true })
  @Field()
  executionPrice: string;

  @Prop({ required: true })
  @Field()
  user: string;

  @Prop({ required: true })
  @Field()
  typeOfOrder: number;
}

export type SwapDocument = Swap & Document;
export const SwapSchema = SchemaFactory.createForClass(Swap);
