import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';
import { Field, ObjectType, Int } from '@nestjs/graphql';

export type TokenDocument = Token & Document;

@ObjectType() // GraphQL type
@Schema()
export class Token {
  @Field(() => String)
  @Prop({ required: true })
  name: string;

  @Field(() => String)
  @Prop({ required: true })
  symbol: string;

  @Field(() => String)
  @Prop({
    required: true,
    unique: true,
    set: (value: string) => value.toLowerCase(),
  })
  address: string;

  @Field(() => Int)
  @Prop({ required: true })
  decimals: number;

  @Field(() => String, { nullable: true })
  @Prop()
  image_url: string;
}

export const TokenSchema = SchemaFactory.createForClass(Token);
