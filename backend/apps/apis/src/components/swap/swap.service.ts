import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Swap, SwapDocument } from '@app/database/schemas/swap.schema';
import {
  SwapStream,
  SwapStreamDocument,
} from '@app/database/schemas/swap.stream.schema';
import { CreateSwapInput } from './dto/create.swap.input';
import { CreateSwapStreamInput } from './dto/create.swap.stream.input';

@Injectable()
export class SwapService {
  constructor(
    @InjectModel(Swap.name) private readonly swapModel: Model<SwapDocument>,
    @InjectModel(SwapStream.name)
    private readonly swapStreamModel: Model<SwapStreamDocument>,
  ) {}

  async createSwap(data: CreateSwapInput): Promise<Swap> {
    const createdSwap = new this.swapModel(data);
    return createdSwap.save();
  }

  async createSwapStream(data: CreateSwapStreamInput): Promise<SwapStream> {
    const createdSwapStream = new this.swapStreamModel(data);
    return createdSwapStream.save();
  }

  async findAllSwaps(): Promise<Swap[]> {
    return this.swapModel.find().exec();
  }

  async findAllSwapStreams(): Promise<SwapStream[]> {
    return this.swapStreamModel.find().exec();
  }

  async findSwapWithStreams(
    swapId: number,
  ): Promise<{ swap: Swap; streams: SwapStream[] }> {
    const swap = await this.swapModel.findOne({ swapId }).exec();

    if (!swap) throw new Error('Swap not found');

    const streams = await this.swapStreamModel.find({ swapId }).exec();
    return { swap, streams };
  }
}
