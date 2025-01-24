import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Event } from './schemas/event.schema';

@Injectable()
export class MonitoringService implements OnModuleInit {
  private readonly logger = new Logger(MonitoringService.name);

  constructor(@InjectModel(Event.name) private eventModel: Model<Event>) {}

  onModuleInit() {
    this.startMonitoring();
  }

  startMonitoring() {
    this.logger.log('Monitoring Events');
  }

  private async cacheEvent(event: { id: string; eventData: string }) {
    const newEvent = new this.eventModel(event);
    await newEvent.save();
  }
}
