import { Resolver, Query, Mutation, Args } from '@nestjs/graphql';

import { TokenService } from './token.service';
import { Token } from '@app/database/schemas/token.schema';
import { CreateTokenInput } from './dto/create.token.dto';
import { UpdateTokenInput } from './dto/update.token.dto';

@Resolver(() => Token)
export class TokenResolver {
  constructor(private readonly tokenService: TokenService) {}

  @Query(() => [Token], { name: 'getAllTokens' })
  findAll() {
    return this.tokenService.findAll();
  }

  @Query(() => Token, { name: 'getTokenByAddress' })
  findOne(@Args('address', { type: () => String }) address: string) {
    return this.tokenService.findOne(address);
  }

  @Mutation(() => Token)
  createToken(@Args('createTokenInput') createTokenInput: CreateTokenInput) {
    return this.tokenService.createToken(createTokenInput);
  }

  @Mutation(() => Token)
  updateToken(
    @Args('address', { type: () => String }) address: string,
    @Args('updateTokenInput') updateTokenInput: UpdateTokenInput,
  ) {
    return this.tokenService.updateToken(address, updateTokenInput);
  }

  @Mutation(() => Token)
  deleteToken(@Args('address', { type: () => String }) address: string) {
    return this.tokenService.deleteToken(address);
  }
}
