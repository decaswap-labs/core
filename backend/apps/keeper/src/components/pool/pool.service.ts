import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Pool, PoolDocument } from '@app/database/schemas/pool.schema';

@Injectable()
export class PoolService {
  constructor(
    @InjectModel(Pool.name) private readonly poolModel: Model<PoolDocument>,
  ) {}

  async getPoolsWithOutstandingTrades(): Promise<Pool[]> {
    return this.poolModel.find({ outstandingTrades: { $gt: 0 } }).exec();
  }
}
