import { HttpAdapterHost, NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { Logger } from '@nestjs/common';
import { AllExceptionsFilter } from '@app/utils/filters/all.exceptions.filter';
import { InvalidFormExceptionFilter } from '@app/utils/filters/invalid.form.exception.filter';
import { setupApolloServer } from './apollo.server';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Initialize the app first
  await app.init();

  await setupApolloServer(app);

  app.useGlobalFilters(
    new AllExceptionsFilter(app.get(HttpAdapterHost)),
    new InvalidFormExceptionFilter(),
  );

  const port = process.env.BE_PORT ?? 3000;
  await app.listen(port);

  Logger.log(
    `Application is running on: http://localhost:${port}`,
    'Bootstrap',
  );
}
void bootstrap();
