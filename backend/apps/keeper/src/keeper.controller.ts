import { Controller, Get } from '@nestjs/common';
import { KeeperService } from './keeper.service';

@Controller()
export class KeeperController {
  constructor(private readonly keeperService: KeeperService) {}

  @Get()
  getHello(): string {
    return this.keeperService.getHello();
  }
}
