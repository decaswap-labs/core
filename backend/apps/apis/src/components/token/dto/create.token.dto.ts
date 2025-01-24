import { InputType, Field, Int } from '@nestjs/graphql';
import { IsString, IsInt, IsOptional, IsUrl } from 'class-validator';

@InputType()
export class CreateTokenInput {
  @Field(() => String)
  @IsString()
  name: string;

  @Field(() => String)
  @IsString()
  symbol: string;

  @Field(() => String)
  @IsString()
  address: string;

  @Field(() => Int)
  @IsInt()
  decimals: number;

  @Field(() => String, { nullable: true })
  @IsOptional()
  @IsUrl()
  image_url?: string;
}
