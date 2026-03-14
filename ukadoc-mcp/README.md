# ukadoc-mcp

MCP server for SSP ukadoc documentation.

## 功能

- `search_ukadoc`: Search ukadoc documentation for sakura script functions and properties
- `get_ukadoc_page`: Get a specific page from ukadoc documentation
- `list_ukadoc_categories`: List all available categories in ukadoc documentation

## 安装

```bash
npm install
npm run build
```

## 使用

在 Claude Desktop 或其他 MCP 客户端中配置：

```json
{
  "mcpServers": {
    "ukadoc-mcp": {
      "command": "node",
      "args": ["/path/to/ukadoc-mcp/dist/index.js"]
    }
  }
}
```

## 参考 URL

- https://ssp.shillest.net/ukadoc/manual/
- https://ssp.shillest.net/
- http://usada.sakura.vg/contents/specification.html
- http://crow.aqrs.jp/reference/all/
- https://www.ooyashima.net/db/
