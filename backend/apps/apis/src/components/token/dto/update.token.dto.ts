import { InputType, PartialType } from '@nestjs/graphql';

import { CreateTokenInput } from './create.token.dto';

@InputType()
export class UpdateTokenInput extends PartialType(CreateTokenInput) {}
