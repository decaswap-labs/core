import { Module } from '@nestjs/common';
import { ApolloService } from './apollo.service';
import { MyConfigModule } from '@app/utils/config/my.config.module';

@Module({
  imports: [MyConfigModule],
  providers: [ApolloService],
  exports: [ApolloService], // Export for other modules to use
})
export class ApolloModule {}
