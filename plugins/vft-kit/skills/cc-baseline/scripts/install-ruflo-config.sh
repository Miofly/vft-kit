#!/usr/bin/env bash
# 生成 ~/.claude-flow/config.json（cc-baseline 要求的 ruflo 配置文件）。
#
# 为什么需要这个脚本：
#   `claude-flow init` 只生成 `config.yaml`（V3 运行时配置），不生成 `config.json`。
#   而重跑 init 补 json 的代价很大——它会**无视 --skip-claude / --no-global**，
#   再往 $HOME 写一遍 .claude/{skills,commands,agents,helpers}、CLAUDE.md、AGENTS.md、
#   .agents/、.mcp.json，并且**删掉 ~/.claude/settings.json 的 model 键**（实测 2026-08）。
#   所以这里直接从已有 config.yaml 转出 json，不碰 init。
set -euo pipefail

DIR="$HOME/.claude-flow"
YAML="$DIR/config.yaml"
JSON="$DIR/config.json"

[ -f "$JSON" ] && { echo "✓ $JSON 已存在，跳过"; exit 0; }

if [ ! -f "$YAML" ]; then
  echo "✗ 找不到 $YAML —— 先在家目录跑一次 claude-flow init（注意它会污染 \$HOME，见本脚本头部注释）" >&2
  exit 1
fi

node -e '
const fs=require("fs");
const y=fs.readFileSync(process.argv[1],"utf8");
// 极简 yaml→json：只覆盖 ruflo config.yaml 的结构（缩进 map + 标量，无数组/多行字符串）
const root={};const stack=[{ind:-1,obj:root}];
for(const raw of y.split("\n")){
  if(!raw.trim()||raw.trim().startsWith("#"))continue;
  const ind=raw.match(/^ */)[0].length;
  const line=raw.trim().replace(/\s+#.*$/,"");
  const m=line.match(/^([\w.-]+):\s*(.*)$/); if(!m)continue;
  while(stack.length&&stack[stack.length-1].ind>=ind)stack.pop();
  const parent=stack[stack.length-1].obj;
  const [,k,v]=m;
  if(v===""){const o={};parent[k]=o;stack.push({ind,obj:o});}
  else{let val=v.replace(/^"(.*)"$/,"$1");
    if(val==="true")val=true;else if(val==="false")val=false;
    else if(/^-?\d+$/.test(val))val=+val;
    parent[k]=val;}
}
if(!Object.keys(root).length)throw new Error("解析出空对象，config.yaml 结构可能变了");
fs.writeFileSync(process.argv[2],JSON.stringify(root,null,2)+"\n");
console.log("✓ 已生成 "+process.argv[2]+"（顶层键："+Object.keys(root).join(", ")+"）");
' "$YAML" "$JSON"
