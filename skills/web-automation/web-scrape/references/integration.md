# 集成到项目

## 集成到项目

### 在 Claude Code 中调用

```typescript
// 在其他 skill 中调用
const { execSync } = require('child_process');
const skillDir = '/path/to/vft-kit/skills/web-automation/web-scrape';

const result = execSync(
  `node ${skillDir}/scripts/scrape.mjs ${url} --format markdown --out ${outDir}`,
  { encoding: 'utf8' }
);

// 解析输出获取文件路径
const output = JSON.parse(result);
console.log('Markdown 文件:', output.files.markdown);
```

### 作为 MCP 工具暴露

可以将调度逻辑包装成 MCP tool，让 AI Agent 直接调用。参考 `docs/mcp-integration.md`（TODO）。
