import { Injectable, OnModuleInit } from '@nestjs/common';
import { ApolloClient, InMemoryCache, gql, ApolloError } from '@apollo/client';
import { MyConfigService } from '@app/utils/config/my.config.service';

@Injectable()
export class ApolloService implements OnModuleInit {
  private client: ApolloClient<any>;

  constructor(private readonly configService: MyConfigService) {}

  onModuleInit() {
    this.client = new ApolloClient({
      uri: this.configService.get('GRAPH_URL'), // Replace with your subgraph endpoint
      cache: new InMemoryCache(),
    });
  }

  async querySubgraph<T>(
    query: string,
    variables?: Record<string, any>,
  ): Promise<T> {
    try {
      const response = await this.client.query<T>({
        query: gql`
          ${query}
        `,
        variables,
      });
      return response.data;
    } catch (error: unknown) {
      if (error instanceof ApolloError) {
        throw new Error(`Failed to query subgraph: ${error.message}`);
      }
      throw new Error('Failed to query subgraph: Unknown error occurred.');
    }
  }
}
