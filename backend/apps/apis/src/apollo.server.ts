import { INestApplication } from '@nestjs/common';
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { GraphQLSchemaHost } from '@nestjs/graphql';
import { json } from 'body-parser';
import cors from 'cors';

export async function setupApolloServer(app: INestApplication) {
  // Retrieve the GraphQL schema from the GraphQLSchemaHost
  const graphqlSchemaHost = app.get(GraphQLSchemaHost);
  const schema = graphqlSchemaHost.schema;

  const apolloServer = new ApolloServer({
    schema, // Pass the schema explicitly
  });

  await apolloServer.start();
  // eslint-disable-next-line @typescript-eslint/no-unsafe-call
  app.use('/graphql', cors(), json(), expressMiddleware(apolloServer));
}
