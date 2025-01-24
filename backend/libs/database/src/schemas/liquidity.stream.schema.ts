import { ObjectType, Field, registerEnumType } from '@nestjs/graphql';
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

export enum LiquidityStreamType {
  AddLiquidity = 'AddLiquidity',
  RemoveLiquidity = 'RemoveLiquidity',
}

registerEnumType(LiquidityStreamType, {
  name: 'LiquidityStreamType',
});

@Schema({ id: false })
@ObjectType()
export class LiquidityStream {
  @Prop({ required: true, index: true })
  @Field()
  id: number;

  @Prop({ required: true })
  @Field()
  token: string;

  @Prop({ required: true })
  @Field()
  user: string;

  @Prop({ required: true })
  @Field()
  amount: string;

  @Prop({ required: true })
  @Field()
  streamCount: number;

  @Prop({ required: true })
  @Field()
  streamExecuted: number;

  @Prop({ required: true, enum: LiquidityStreamType, index: true })
  @Field(() => LiquidityStreamType)
  type: LiquidityStreamType;
}

export type LiquidityDocument = LiquidityStream & Document;
export const LiquidityStreamSchema =
  SchemaFactory.createForClass(LiquidityStream);
LiquidityStreamSchema.index({ id: 1, type: 1 }, { unique: true });
