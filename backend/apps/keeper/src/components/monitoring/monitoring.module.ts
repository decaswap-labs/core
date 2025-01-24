import { Module } from '@nestjs/common';
import { MonitoringService } from './monitoring.service';
import { MyConfigModule } from '@app/utils/config/my.config.module';
import { MongooseModule } from '@nestjs/mongoose';
import { Event, EventSchema } from './schemas/event.schema';

@Module({
  imports: [
    MyConfigModule,
    MongooseModule.forFeature([{ name: Event.name, schema: EventSchema }]),
  ],
  providers: [MonitoringService],
  exports: [MonitoringService],
})
export class MonitoringModule {}
