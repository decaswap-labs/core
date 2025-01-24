import { MiddlewareConsumer, Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { DatabaseModule } from '@app/database';
import { GraphQLModule } from '@nestjs/graphql';
import { ApolloDriver, ApolloDriverConfig } from '@nestjs/apollo';
import { PoolModule } from './components/pool/pool.module';
import { TokenModule } from './components/token/token.module';
import { SwapModule } from './components/swap/swap.module';
import { LiquidityStreamModule } from './components/liquidity.stream/liquidity.stream.module';
import { LoggerMiddleware } from '@app/utils/middlewares/logger.middleware';
import { ApolloModule } from './components/apollo/apollo.module';
import { SubgraphEventCron } from './components/crons/subgraph.event.cron';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // Makes ConfigModule available globally
      envFilePath: '.env', // Path to the .env file
    }),
    ScheduleModule.forRoot(),
    GraphQLModule.forRoot<ApolloDriverConfig>({
      driver: ApolloDriver,
      autoSchemaFile: true, // Automatically generates schema
    }),
    DatabaseModule,
    PoolModule,
    TokenModule,
    SwapModule,
    LiquidityStreamModule,
    ApolloModule,
  ],
  controllers: [AppController],
  providers: [AppService, SubgraphEventCron],
})
export class AppModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggerMiddleware).forRoutes('*');
  }
}
