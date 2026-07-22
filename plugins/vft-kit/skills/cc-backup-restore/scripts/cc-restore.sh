#!/bin/bash
# Claude Code 配置恢复脚本
# 用途：换账号 / 重装 / 换机后，把 cc-backup.sh 产出的备份目录恢复回 ~/.claude
#
# 用法：
#   bash cc-restore.sh <备份目录>        # 指定备份目录
#   bash cc-restore.sh                    # 缺省时用脚本自身所在目录（备份目录里自带这份脚本）
#   bash cc-restore.sh <备份目录> -y      # 跳过覆盖确认（非交互）
#
# 职责边界（重要）：本脚本只做「把备份搬回来」，不装任何软件、不改权限模式。
# 想核对个人基线（权限白名单 / RTK / 常用 MCP），跑 cc-baseline。

set -e

ASSUME_YES=0
BACKUP_DIR=""
for arg in "$@"; do
    if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
        ASSUME_YES=1
    elif [ -z "$BACKUP_DIR" ]; then
        BACKUP_DIR="$arg"
    fi
done

# 缺省备份目录 = 脚本自身所在目录（备份目录里就带着这份 cc-restore.sh）
if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ ! -f "$BACKUP_DIR/MANIFEST.txt" ]; then
    echo "❌ $BACKUP_DIR 不像一个 cc-backup 产出的备份目录（缺 MANIFEST.txt）"
    exit 1
fi

echo "🔄 开始恢复 Claude Code 配置..."
echo "📁 备份目录: $BACKUP_DIR"
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
    read -p "⚠️  这将覆盖当前 ~/.claude 下的同名配置（被覆盖的文件会存成 .pre-restore-$STAMP.bak），是否继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ 已取消"
        exit 0
    fi
fi

mkdir -p "$CLAUDE_DIR"

# 覆盖前留回滚点：把即将被覆盖的现有文件另存一份。
# 注意末尾的 return 0：目标文件不存在（全新机器）时 [ -f ] 返回 1，
# 若让它成为函数返回值，set -e 会让整个恢复静默终止——恰好在最该工作的场景。
backup_existing() {
    local f="$1"
    [ -f "$f" ] && cp "$f" "$f.pre-restore-$STAMP.bak"
    return 0
}

# 1. 恢复顶层 md（CLAUDE.md 及其 @ 引用的同级 md，如 RTK.md）
echo ""
echo "📄 恢复全局 md..."
for md in "$BACKUP_DIR"/*.md; do
    [ -f "$md" ] || continue
    name=$(basename "$md")
    # README.md 是备份目录自己的说明，不属于 CC 配置
    [ "$name" = "README.md" ] && continue
    backup_existing "$CLAUDE_DIR/$name"
    cp "$md" "$CLAUDE_DIR/"
    echo "  ✓ $name"
done

# 2. 恢复 settings.json（合并，而非覆盖）
echo ""
echo "⚙️  恢复 settings.json..."
if [ -f "$BACKUP_DIR/settings.json" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "  ⚠️  未安装 jq，跳过 settings.json 合并（brew install jq 后重跑，或手动合并）"
    else
        [ -f "$CLAUDE_DIR/settings.json" ] || echo '{}' > "$CLAUDE_DIR/settings.json"
        backup_existing "$CLAUDE_DIR/settings.json"
        # 当前 live 配置为底，备份覆盖结构项。备份里已不含 env/oauth（备份时就剔除了），
        # 这里再 del 一次是防御：即使拿到的是老格式备份，也绝不把旧 token / 代理注回新号。
        jq -s '.[0] * (.[1] | del(.env, .oauthAccount, .oauthToken))' \
            "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json" \
            > "$CLAUDE_DIR/settings.json.tmp"
        mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
        echo "  ✓ settings.json（已合并；当前登录身份 / env 保持不动）"
    fi
fi

if [ -f "$BACKUP_DIR/settings.local.json" ]; then
    backup_existing "$CLAUDE_DIR/settings.local.json"
    cp "$BACKUP_DIR/settings.local.json" "$CLAUDE_DIR/"
    echo "  ✓ settings.local.json"
fi

# 3. 恢复插件（清单 + marketplace 源，两者缺一不可）
echo ""
echo "🔌 恢复插件..."
if [ -d "$BACKUP_DIR/plugins" ]; then
    mkdir -p "$CLAUDE_DIR/plugins"
    for f in installed_plugins.json known_marketplaces.json config.json; do
        if [ -f "$BACKUP_DIR/plugins/$f" ]; then
            backup_existing "$CLAUDE_DIR/plugins/$f"
            cp "$BACKUP_DIR/plugins/$f" "$CLAUDE_DIR/plugins/"
            echo "  ✓ $f"
        fi
    done
    echo "  → 插件将在下次启动 CC 时按清单自动重装"
    # directory 型 marketplace（自建插件仓库）靠绝对路径引用，换机后路径不存在就装不回来。
    # 逐个校验目标机上是否真有这个路径，缺的直接点名——不然只会在启动时静默少几个插件。
    if [ -f "$BACKUP_DIR/plugins/known_marketplaces.json" ] && command -v jq >/dev/null 2>&1; then
        missing=0
        while IFS=$'\t' read -r mp_name mp_path; do
            [ -n "$mp_path" ] || continue
            if [ ! -d "$mp_path" ]; then
                [ "$missing" = 0 ] && echo "  ⚠️  以下本地 marketplace 在本机不存在，其插件将无法恢复："
                echo "     $mp_name → $mp_path"
                missing=1
            fi
        done < <(jq -r 'to_entries[] | select(.value.source.source == "directory")
                        | "\(.key)\t\(.value.source.path)"' \
                 "$BACKUP_DIR/plugins/known_marketplaces.json" 2>/dev/null)
        [ "$missing" = 1 ] && echo "     → 把这些仓库 clone 到同路径后重启 CC，或用 /plugin marketplace add 重指向新路径"
    fi
fi

# 4. 恢复项目记忆
echo ""
echo "🧠 恢复项目记忆..."
if [ -d "$BACKUP_DIR/memory" ]; then
    for project_memory in "$BACKUP_DIR/memory"/*; do
        [ -d "$project_memory" ] || continue
        # 目录名就是备份时 CC 对 cwd 的 sanitize 结果，原样还原
        project_name=$(basename "$project_memory")
        target_dir="$CLAUDE_DIR/projects/$project_name/memory"
        mkdir -p "$target_dir"
        cp -r "$project_memory/"* "$target_dir/" 2>/dev/null || true
        count=$(ls -1 "$target_dir" 2>/dev/null | wc -l | tr -d ' ')
        echo "  ✓ $project_name ($count 个文件)"
    done
else
    echo "  ⊘ 备份中无项目记忆"
fi

# 5. 恢复 hooks / skills / agents / commands
for d in hooks skills agents commands; do
    echo ""
    echo "📂 恢复 $d..."
    if [ -d "$BACKUP_DIR/$d" ] && [ "$(ls -A "$BACKUP_DIR/$d" 2>/dev/null)" ]; then
        mkdir -p "$CLAUDE_DIR/$d"
        cp -r "$BACKUP_DIR/$d/"* "$CLAUDE_DIR/$d/" 2>/dev/null || true
        count=$(ls -1 "$CLAUDE_DIR/$d" 2>/dev/null | wc -l | tr -d ' ')
        echo "  ✓ $d ($count 个条目)"
    else
        echo "  ⊘ 备份中无 $d"
    fi
done

# 6. 校验 settings.json 里 hook 引用的本地脚本是否都在
#    hook 的 command 可以指向任意本地脚本（不止 hooks/ 目录，如公司监控的 cc-otel/*.js、
#    ~/.cc-helper/*.sh）。备份只搬固定几个资产目录，换机 / 换号后这些「目录外」的脚本可能
#    根本不在——CC 每次触发该事件就 MODULE_NOT_FOUND / command not found 刷屏。
#    这里逐个点名缺失的，和上面 directory 型 marketplace 校验同一套路，别让它在启动后静默报错。
echo ""
echo "🔎 校验 hook 引用的本地脚本..."
if [ -f "$CLAUDE_DIR/settings.json" ] && command -v jq >/dev/null 2>&1; then
    hook_missing=0
    # 从所有 hook 的 command 里抠出「带脚本扩展名的文件路径」；裸命令（rtk / node / python3）不算
    while IFS= read -r script_path; do
        [ -n "$script_path" ] || continue
        # 展开 ~ / $HOME，其余原样
        expanded="${script_path/#\~/$HOME}"
        expanded="${expanded/#\$HOME/$HOME}"
        if [ ! -e "$expanded" ]; then
            [ "$hook_missing" = 0 ] && echo "  ⚠️  以下 hook 引用的脚本在本机不存在，触发对应事件时会报错："
            echo "     $script_path"
            hook_missing=1
        fi
    done < <(jq -r '.hooks // {} | [.. | .command?] | map(select(. != null)) | .[]' \
                 "$CLAUDE_DIR/settings.json" 2>/dev/null \
             | grep -oE '(\$HOME|~|/)[A-Za-z0-9._/-]*\.(js|mjs|cjs|ts|py|sh|bash)' \
             | sort -u)
    if [ "$hook_missing" = 1 ]; then
        echo "     → 要么把脚本补到该路径，要么用 jq 从 ~/.claude/settings.json 的 .hooks 里删掉对应项"
    else
        echo "  ✓ 全部就位"
    fi
else
    echo "  ⊘ 跳过（无 settings.json 或未装 jq）"
fi

# 7. Playwright MCP 的 --output-dir 需插件装好后再补
if [ -f "$BACKUP_DIR/plugins/cache/playwright/.mcp.json" ]; then
    echo ""
    echo "📦 Playwright MCP 配置（需插件装好后手动补）："
    echo "   备份留档: $BACKUP_DIR/plugins/cache/playwright/.mcp.json"
    echo "   等插件自动安装完成后，把该文件里的 --output-dir 参数补回："
    echo "   ~/.claude/plugins/cache/claude-plugins-official/playwright/*/.mcp.json"
fi

echo ""
echo "✅ 恢复完成！被覆盖的旧文件已存为 *.pre-restore-$STAMP.bak"
echo ""
echo "📌 后续："
echo "   1. 重启 Claude Code 让配置与插件生效（插件下载可能要几分钟）"
echo "   2. 想核对个人基线（权限白名单 / RTK / 常用 MCP）→ 另跑 cc-baseline"
echo ""
