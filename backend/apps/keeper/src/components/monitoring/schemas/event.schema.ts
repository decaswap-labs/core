import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

@Schema()
export class Event extends Document {
  @Prop({ required: true, unique: true })
  id: string;

  @Prop({ required: true })
  eventName: string;

  @Prop({ required: true })
  eventData: string;

  @Prop({ default: Date.now })
  timestamp: Date;
}

export const EventSchema = SchemaFactory.createForClass(Event);
