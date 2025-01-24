import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Pool, PoolDocument } from '@app/database/schemas/pool.schema';
import { CreatePoolInput } from './dto/create.pool.input';

@Injectable()
export class PoolService {
  constructor(
    @InjectModel(Pool.name) private readonly poolModel: Model<PoolDocument>,
  ) {}

  async createPool(data: CreatePoolInput): Promise<Pool> {
    const createdPool = new this.poolModel(data);
    return createdPool.save();
  }

  async findAllPools(): Promise<Pool[]> {
    return this.poolModel.find().exec();
  }
}
