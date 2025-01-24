import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response } from 'express';

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: CallableFunction): void {
    console.log(
      `[API Request] ${req.method} ${req.originalUrl}: ${JSON.stringify(
        req.body,
      )}`,
    );
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call
    next();
  }
}
