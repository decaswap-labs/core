import { Injectable, Logger } from '@nestjs/common';
import { ethers } from 'ethers';
import { MyConfigService } from '@app/utils/config/my.config.service';
import RouterAbi from '@app/utils/abis/router.json';
import { PoolService } from '../pool/pool.service';

@Injectable()
export class ExecutionService {
  private signer: ethers.Wallet;
  private contract: ethers.Contract;
  private readonly logger = new Logger(ExecutionService.name);

  constructor(
    private readonly configService: MyConfigService,
    private readonly poolService: PoolService,
  ) {
    const provider = new ethers.providers.JsonRpcProvider(
      this.configService.get('RPC_URL'),
    );
    this.signer = new ethers.Wallet(
      this.configService.get('PRIVATE_KEY'),
      provider,
    );
    this.contract = new ethers.Contract(
      this.configService.get('ROUTER_ADDRESS'),
      RouterAbi, // Replace with contract ABI
      this.signer,
    );
  }

  async callMaintenance(): Promise<void> {
    try {
      const pools = await this.poolService.getPoolsWithOutstandingTrades();
      this.logger.log(
        `Processing ${pools.length} pools with outstanding trades`,
      );

      for (const pool of pools) {
        this.logger.log(
          `Processing pool ${pool.pairId} with outstanding trades = ${pool.outstandingTrades}`,
        );

        /*  const tx = await this.contract.maintenance(pool.pairId);
        console.log(`Transaction sent: ${tx.hash}`);

        const receipt = await tx.wait();
        console.log(`Transaction mined: ${receipt.transactionHash}`);*/
      }
    } catch (error) {
      console.error('Error calling maintenance function', error);
    }
  }
}
