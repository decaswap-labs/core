import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';

import { GET_META } from './queries/query';
import { ApolloService } from '../apollo/apollo.service';

@Injectable()
export class SubgraphEventCron {
  private isCronRunning = false;
  private readonly logger = new Logger(SubgraphEventCron.name);

  constructor(private readonly apolloService: ApolloService) {}

  async getMetaData() {
    const variables = {};
    return this.apolloService.querySubgraph(GET_META, variables);
  }

  @Cron(CronExpression.EVERY_5_SECONDS)
  async handleEverySecond() {
    if (!this.isCronRunning) {
      try {
        this.isCronRunning = true;
        this.logger.log('Task executed every 5 second');
        const metaData = await this.getMetaData();
        this.logger.log('Fetched data:', metaData);
      } catch (e) {
        this.logger.log(e);
      }

      this.isCronRunning = false;
    } else {
      this.logger.log(
        'Cron is already running, please wait for it to finish',
        this.isCronRunning,
      );
    }
  }
}
