import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { Token, TokenSchema } from '@app/database/schemas/token.schema';
import { TokenService } from './token.service';
import { TokenResolver } from './token.resolver';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Token.name, schema: TokenSchema }]),
  ],
  providers: [TokenResolver, TokenService],
})
export class TokenModule {}
