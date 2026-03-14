#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { searchUkadoc, getUkadocPage, listCategories } from './ukadoc.js';

const server = new Server(
  {
    name: 'ukadoc-mcp',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'search_ukadoc',
        description: 'Search SSP ukadoc documentation for sakura script functions and properties',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query (e.g., function name, keyword)',
            },
          },
          required: ['query'],
        },
      },
      {
        name: 'get_ukadoc_page',
        description: 'Get a specific page from ukadoc documentation',
        inputSchema: {
          type: 'object',
          properties: {
            path: {
              type: 'string',
              description: 'Page path (e.g., /manual/list_sakura_script.html)',
            },
          },
          required: ['path'],
        },
      },
      {
        name: 'list_ukadoc_categories',
        description: 'List all available categories in ukadoc documentation',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'search_ukadoc': {
        const query = args?.query as string;
        if (!query) {
          throw new Error('Query is required');
        }
        const results = await searchUkadoc(query);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(results, null, 2),
            },
          ],
        };
      }

      case 'get_ukadoc_page': {
        const path = args?.path as string;
        if (!path) {
          throw new Error('Path is required');
        }
        const content = await getUkadocPage(path);
        return {
          content: [
            {
              type: 'text',
              text: content,
            },
          ],
        };
      }

      case 'list_ukadoc_categories': {
        const categories = await listCategories();
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(categories, null, 2),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            error: error instanceof Error ? error.message : 'Unknown error',
          }),
        },
      ],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('ukadoc-mcp server started');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
