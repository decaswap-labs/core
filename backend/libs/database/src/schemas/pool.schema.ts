import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { ObjectType, Field } from '@nestjs/graphql';
import { Document } from 'mongoose';

@Schema()
@ObjectType()
export class Pool {
  @Prop({ required: true, index: true })
  @Field()
  pairId: string;

  @Prop({ required: true })
  @Field()
  user: string;

  @Prop({ required: true })
  @Field()
  tokenAmount: string;

  @Prop({ required: true })
  @Field()
  dTokenAmount: string;

  @Prop({ required: true, default: 0 })
  @Field(() => Number)
  outstandingTrades: number;
}

export type PoolDocument = Pool & Document;
export const PoolSchema = SchemaFactory.createForClass(Pool);
