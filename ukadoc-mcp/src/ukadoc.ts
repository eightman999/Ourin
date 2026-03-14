const UKADOC_BASE_URL = 'https://ssp.shillest.net/ukadoc';

export interface SearchResult {
  url: string;
  title: string;
  snippet: string;
}

export interface Category {
  name: string;
  path: string;
  description: string;
}

const CATEGORIES: Category[] = [
  {
    name: 'Sakura Script',
    path: '/manual/list_sakura_script.html',
    description: 'Sakura Script function reference',
  },
  {
    name: 'Property System',
    path: '/manual/list_propertysystem.html',
    description: 'Property system documentation',
  },
  {
    name: 'SHIORI 3.0 Specification',
    path: '/manual/spec_shiori3.html',
    description: 'SHIORI 3.0M specification',
  },
  {
    name: 'SSTP Protocol',
    path: '/manual/spec_sstp.html',
    description: 'SSTP 1.xM protocol specification',
  },
  {
    name: 'Plugin 2.0 Specification',
    path: '/manual/spec_plugin.html',
    description: 'Plugin 2.0M specification',
  },
  {
    name: 'Ghost Development Guide',
    path: '/manual/ghost_create.html',
    description: 'Ghost creation guide',
  },
];

export async function searchUkadoc(query: string): Promise<SearchResult[]> {
  const results: SearchResult[] = [];

  for (const category of CATEGORIES) {
    const content = await fetchPage(category.path);
    const lines = content.split('\n');

    for (const line of lines) {
      if (line.toLowerCase().includes(query.toLowerCase())) {
        const matches = line.match(/>([^<]+)</g);
        if (matches) {
          for (const match of matches) {
            const text = match.replace(/^>|</g, '').trim();
            if (text.length > 10) {
              results.push({
                url: `${UKADOC_BASE_URL}${category.path}`,
                title: category.name,
                snippet: text.substring(0, 200),
              });
            }
          }
        }
      }
    }
  }

  return results.slice(0, 20);
}

export async function getUkadocPage(path: string): Promise<string> {
  const url = `${UKADOC_BASE_URL}${path}`;
  const content = await fetchPage(path);
  return content;
}

export async function listCategories(): Promise<Category[]> {
  return CATEGORIES;
}

async function fetchPage(path: string): Promise<string> {
  const url = `${UKADOC_BASE_URL}${path}`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    return await response.text();
  } catch (error) {
    throw new Error(`Failed to fetch ${url}: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}
