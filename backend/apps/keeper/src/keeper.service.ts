import { Injectable } from '@nestjs/common';

@Injectable()
export class KeeperService {
  getHello(): string {
    return 'Hello World!';
  }
}
