import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Token, TokenDocument } from '@app/database/schemas/token.schema';
import { CreateTokenInput } from './dto/create.token.dto';
import { UpdateTokenInput } from './dto/update.token.dto';

@Injectable()
export class TokenService {
  constructor(
    @InjectModel(Token.name) private tokenModel: Model<TokenDocument>,
  ) {}

  /**
   * Create a new token
   * @param createTokenInput - Data for creating a token
   * @returns The created token document
   */
  async createToken(createTokenInput: CreateTokenInput): Promise<Token> {
    const token = new this.tokenModel(createTokenInput);
    return token.save();
  }

  /**
   * Retrieve all tokens
   * @returns Array of all token documents
   */
  async findAll(): Promise<Token[]> {
    return this.tokenModel.find().exec();
  }

  /**
   * Retrieve a single token by its address
   * @param address - The address of the token
   * @returns The token document if found, or null
   */
  async findOne(address: string): Promise<Token | null> {
    return this.tokenModel.findOne({ address }).exec();
  }

  /**
   * Update a token by its address
   * @param address - The address of the token to update
   * @param updateTokenInput - The updated data for the token
   * @returns The updated token document if successful, or null
   */
  async updateToken(
    address: string,
    updateTokenInput: UpdateTokenInput,
  ): Promise<Token | null> {
    return this.tokenModel
      .findOneAndUpdate({ address }, updateTokenInput, { new: true })
      .exec();
  }

  /**
   * Delete a token by its address
   * @param address - The address of the token to delete
   * @returns The deleted token document if successful, or null
   */
  async deleteToken(address: string): Promise<Token | null> {
    return this.tokenModel.findOneAndDelete({ address }).exec();
  }
}
