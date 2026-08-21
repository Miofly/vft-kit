#!/bin/bash
# Claude Code 配置备份脚本
# 用途：换号 / 重装 / 换机前，把 ~/.claude 下的「配置与数据」打包成自包含备份目录
#
# 产出：$CC_BACKUP_ROOT（默认 ~/cc-backups）/cc-backup-<时间戳>/
#       目录自包含：内含 cc-restore.sh + README.md + MANIFEST.txt，拷到任何机器都能独立恢复
# 恢复：cd 进备份目录 → bash cc-restore.sh
#
# 不备份登录态：settings.json 的 env / oauthAccount / oauthToken 在备份时就已剔除
# （旧 token 既没用又是风险；跨机免登录请用 cc-auth-migrate）。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${CC_BACKUP_ROOT:-$HOME/cc-backups}"
BACKUP_DIR="$BACKUP_ROOT/cc-backup-$(date +%Y%m%d-%H%M%S)"
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "❌ 未找到 $CLAUDE_DIR，没什么可备份的"
    exit 1
fi

echo "🔄 开始备份 Claude Code 配置..."
echo "📁 备份目录: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

HAS_JQ=0
command -v jq >/dev/null 2>&1 && HAS_JQ=1
[ "$HAS_JQ" = 0 ] && echo "⚠️  未安装 jq（brew install jq）：settings.json 将原样拷贝，敏感 env 不会被剔除"

# 1. 顶层 md：CLAUDE.md 以及它 @ 引用的同级 md（如 RTK.md），一并带走保证引用闭合
echo ""
echo "📄 备份全局 md..."
for md in "$CLAUDE_DIR"/*.md; do
    [ -f "$md" ] || continue
    cp "$md" "$BACKUP_DIR/"
    echo "  ✓ $(basename "$md")"
done

# 2. settings：备份时即剔除 env / oauthAccount / oauthToken
#    —— 恢复时本就不会用它们，留在备份里只是把代理凭据 / OTEL 端点 / token 摊在磁盘上。
echo ""
echo "⚙️  备份 settings..."
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if [ "$HAS_JQ" = 1 ]; then
        jq 'del(.env, .oauthAccount, .oauthToken)' "$CLAUDE_DIR/settings.json" > "$BACKUP_DIR/settings.json"
        echo "  ✓ settings.json（env / oauth 已剔除）"
    else
        cp "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/"
        echo "  ⚠️  settings.json（原样拷贝，含敏感 env——勿提交 git / 勿外传）"
    fi
fi
if [ -f "$CLAUDE_DIR/settings.local.json" ]; then
    if [ "$HAS_JQ" = 1 ]; then
        jq 'del(.env, .oauthAccount, .oauthToken)' "$CLAUDE_DIR/settings.local.json" > "$BACKUP_DIR/settings.local.json"
    else
        cp "$CLAUDE_DIR/settings.local.json" "$BACKUP_DIR/"
    fi
    echo "  ✓ settings.local.json"
fi

# 3. 插件：清单 + marketplace 源。
#    只备份 installed_plugins.json 是不够的——它引用 marketplace，
#    源定义丢了，自建 / 私有 marketplace 的插件恢复时无从下载。
echo ""
echo "🔌 备份插件配置..."
mkdir -p "$BACKUP_DIR/plugins"
for f in installed_plugins.json known_marketplaces.json config.json; do
    if [ -f "$CLAUDE_DIR/plugins/$f" ]; then
        cp "$CLAUDE_DIR/plugins/$f" "$BACKUP_DIR/plugins/"
        echo "  ✓ $f"
    fi
done
if [ "$HAS_JQ" = 1 ] && [ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ]; then
    # v2 格式：.plugins 是 object，key = "插件名@marketplace"，value = 各 scope 的安装记录数组
    jq -r '(.plugins // {}) | to_entries[] | "\(.key)  [\(.value | map(.scope) | join(","))]"' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null \
        | sort > "$BACKUP_DIR/plugins/plugin-list.txt" || true
    [ -s "$BACKUP_DIR/plugins/plugin-list.txt" ] && echo "  ✓ plugin-list.txt（人读清单，$(wc -l < "$BACKUP_DIR/plugins/plugin-list.txt" | tr -d ' ') 个插件）"
fi

# 4. 项目记忆（遍历所有项目，不特判任何一个）
echo ""
echo "🧠 备份项目记忆..."
# 目录名是 CC 对 cwd 的 sanitize 结果（如 -Users-me-code-foo），原样保留即可无损还原
found_any=0
for project_dir in "$CLAUDE_DIR"/projects/*/; do
    [ -d "$project_dir" ] || continue
    memory_dir="${project_dir}memory"
    [ -d "$memory_dir" ] || continue
    project_name=$(basename "$project_dir")
    mkdir -p "$BACKUP_DIR/memory/$project_name"
    cp -r "$memory_dir/"* "$BACKUP_DIR/memory/$project_name/" 2>/dev/null || true
    count=$(ls -1 "$memory_dir" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✓ $project_name ($count 个文件)"
    found_any=1
done
[ "$found_any" = 0 ] && echo "  ⊘ 没有找到任何项目记忆"

# 5. 用户资产目录：hooks / skills / agents / commands
for d in hooks skills agents commands; do
    echo ""
    echo "📂 备份 $d..."
    if [ -d "$CLAUDE_DIR/$d" ] && [ "$(ls -A "$CLAUDE_DIR/$d" 2>/dev/null)" ]; then
        mkdir -p "$BACKUP_DIR/$d"
        cp -r "$CLAUDE_DIR/$d/"* "$BACKUP_DIR/$d/" 2>/dev/null || true
        count=$(ls -1 "$CLAUDE_DIR/$d" 2>/dev/null | wc -l | tr -d ' ')
        echo "  ✓ $d ($count 个条目)"
    else
        echo "  ⊘ 无 $d"
    fi
done

# 6. Playwright MCP 的 .mcp.json（含 --output-dir 定制，插件重装会覆盖，留个档好手动补回）
echo ""
echo "📦 备份关键插件配置..."
PLAYWRIGHT_MCP="$CLAUDE_DIR/plugins/cache/claude-plugins-official/playwright"
if [ -d "$PLAYWRIGHT_MCP" ]; then
    mkdir -p "$BACKUP_DIR/plugins/cache/playwright"
    find "$PLAYWRIGHT_MCP" -name ".mcp.json" -exec cp {} "$BACKUP_DIR/plugins/cache/playwright/" \; 2>/dev/null || true
    echo "  ✓ Playwright MCP .mcp.json"
else
    echo "  ⊘ 未装 Playwright 插件"
fi

# 7. 把恢复脚本原样拷进备份目录（自包含；单一来源，不再内嵌副本）
cp "$SCRIPT_DIR/cc-restore.sh" "$BACKUP_DIR/cc-restore.sh"
chmod +x "$BACKUP_DIR/cc-restore.sh"

# 8. README + 清单
cat > "$BACKUP_DIR/README.md" << EOF
# Claude Code 配置备份

备份时间：$(date)
来源主机：$(hostname)

## 内容

- 全局 md（CLAUDE.md 及其 @ 引用的同级 md）
- settings.json / settings.local.json（**env / oauthAccount / oauthToken 已剔除**）
- 插件：installed_plugins.json + known_marketplaces.json（清单 + 来源，缺一不可）
- 项目记忆 memory/、hooks/、skills/、agents/、commands/
- Playwright MCP 的 .mcp.json 留档

**不含登录态**。跨机免登录请用 cc-auth-migrate。

## 恢复

\`\`\`bash
cd "$BACKUP_DIR"
bash cc-restore.sh        # 交互确认；-y 跳过确认
\`\`\`

恢复只搬配置，不装软件、不改权限模式。被覆盖的旧文件会存成 \`*.pre-restore-<时间戳>.bak\`。

想核对个人基线（权限白名单 / RTK / 常用 MCP）→ 恢复后另跑 cc-baseline。

## 注意

- 自建 / 私有 marketplace 的插件，需要目标机能访问到对应仓库才装得回来。
- 插件在下次启动 CC 时自动重装，可能要几分钟。
- Playwright 的 \`--output-dir\` 需在插件装好后手动补回（参考 plugins/cache/playwright/.mcp.json）。
EOF

{
    echo "Claude Code 配置备份清单"
    echo "生成时间: $(date)"
    echo ""
    echo "=== 文件列表 ==="
} > "$BACKUP_DIR/MANIFEST.txt"
find "$BACKUP_DIR" -type f | sed "s|$BACKUP_DIR/||" | sort >> "$BACKUP_DIR/MANIFEST.txt"

echo ""
echo "✅ 备份完成：$BACKUP_DIR"
echo "   文件数：$(find "$BACKUP_DIR" -type f | wc -l | tr -d ' ')  大小：$(du -sh "$BACKUP_DIR" | cut -f1)"
echo ""
echo "📌 下一步：换号 / 重装 / 换机后 → cd \"$BACKUP_DIR\" && bash cc-restore.sh"
echo ""
