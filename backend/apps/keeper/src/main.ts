import { NestFactory } from '@nestjs/core';
import { KeeperModule } from './keeper.module';
import { Logger } from '@nestjs/common';

async function bootstrap() {
  const app = await NestFactory.create(KeeperModule);
  const port = process.env.KEEPER_PORT ?? 3001;
  await app.listen(port);

  Logger.log(
    `Application is running on: http://localhost:${port}`,
    'Bootstrap',
  );
}
void bootstrap();
