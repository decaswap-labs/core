import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import {
  LiquidityStream,
  LiquidityDocument,
  LiquidityStreamType,
} from '@app/database/schemas/liquidity.stream.schema';
import { CreateLiquidityInput } from './dto/create.liquidity.input';

@Injectable()
export class LiquidityStreamService {
  constructor(
    @InjectModel(LiquidityStream.name)
    private readonly liquidityModel: Model<LiquidityDocument>,
  ) {}

  /**
   * Create a new liquidity stream
   * @param data - Input data for the liquidity stream
   * @returns The created LiquidityStream document
   */
  async createLiquidity(data: CreateLiquidityInput): Promise<LiquidityStream> {
    const createdLiquidity = new this.liquidityModel(data);
    return createdLiquidity.save();
  }

  /**
   * Retrieve all liquidity streams
   * @returns An array of all LiquidityStream documents
   */
  async findAllLiquidities(): Promise<LiquidityStream[]> {
    return this.liquidityModel.find().exec();
  }

  /**
   * Find a liquidity stream by ID and type
   * @param id - The ID of the liquidity stream
   * @param type - The type of the liquidity stream
   * @returns The matching LiquidityStream document
   * @throws NotFoundException if no document is found
   */
  async findLiquidityByIdAndType(
    id: number,
    type: LiquidityStreamType,
  ): Promise<LiquidityStream> {
    const liquidity = await this.liquidityModel.findOne({ id, type }).exec();

    if (!liquidity) {
      throw new NotFoundException(
        `Liquidity stream with ID ${id} and type ${type} not found`,
      );
    }
    return liquidity;
  }
}
