#!/usr/bin/env bash
# 探测前端 dev server 实际监听端口。
# 优先级：项目配置端口(vite/vue.config) -> 框架默认端口 -> 常见备选端口。
# 命中则打印端口号(exit 0)；都没命中打印空行(exit 1)。
# 用法: check-server.sh [项目目录]   省略则用当前目录。
#
# 刻意不依赖 grep/sed/awk：本机 grep 被 volta 转发到未安装的 ugrep 会报错，
# 且 macOS 自带 grep 不支持 -P。纯 bash 正则读端口，零外部依赖，最稳。

set -uo pipefail

DIR="${1:-$PWD}"
cd "$DIR" 2>/dev/null || { echo ""; exit 1; }

# 从配置文件里抠出 dev server 的端口，纯 bash 实现。
#
# 不能简单取"第一个 port:" —— 配置里还有 preview.port（vite preview 的端口）、devServer、
# proxy 段等，谁写在前面就会被抢先命中，探测到一个跟 dev server 无关的端口。
# 所以按所在段落定优先级：server.port > 未归属的 port > preview.port。
extract_port() {
  [ -f "$1" ] || return 1
  local line section="none" p_server="" p_plain="" p_preview=""
  while IFS= read -r line || [ -n "$line" ]; do
    # 段落切换（匹配 `server: {` / `preview: {` / `devServer: {` 这类键）
    if [[ "$line" =~ (^|[[:space:]{,])(server|devServer)[[:space:]]*:[[:space:]]*\{ ]]; then section="server"; fi
    if [[ "$line" =~ (^|[[:space:]{,])preview[[:space:]]*:[[:space:]]*\{ ]]; then section="preview"; fi
    if [[ "$line" =~ port[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
      case "$section" in
        server)  [ -z "$p_server" ]  && p_server="${BASH_REMATCH[1]}" ;;
        preview) [ -z "$p_preview" ] && p_preview="${BASH_REMATCH[1]}" ;;
        *)       [ -z "$p_plain" ]   && p_plain="${BASH_REMATCH[1]}" ;;
      esac
    fi
  done < "$1"
  local p="${p_server:-${p_plain:-$p_preview}}"
  [ -n "$p" ] || return 1
  printf '%s' "$p"
}

ProjectPort=""
for cfg in vite.config.ts vite.config.js vite.config.mts vite.config.mjs vue.config.js; do
  p="$(extract_port "$cfg")" && [ -n "$p" ] && { ProjectPort="$p"; break; }
done

# 框架默认端口
DefaultPort=3000
if ls vite.config.* >/dev/null 2>&1; then
  DefaultPort=5173            # Vite 默认
elif [ -f vue.config.js ]; then
  DefaultPort=8080            # Vue CLI 默认
fi

FirstPort="${ProjectPort:-$DefaultPort}"

port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    nc -z localhost "$1" >/dev/null 2>&1
  else
    return 1
  fi
}

# 「端口被占」≠「跑的是前端 dev server」。常见端口上完全可能是 nginx / 后端 API / 别的项目，
# 认错了不只是测错页面——这个端口会被交给 close-server.sh 去 kill。所以扫出来的候选要验一下：
# 发个 GET，响应必须是 HTML 才认。（配置文件里明写的端口不验，那是用户自己声明的。）
serves_html() {
  command -v node >/dev/null 2>&1 || return 0   # 没 node 就别拦，退回原行为
  node -e "
    const http = require('node:http');
    const req = http.request({ host:'127.0.0.1', port:process.argv[1], path:'/', timeout:2500, family:4 }, r => {
      const ct = String(r.headers['content-type'] || '');
      r.resume();
      process.exit(ct.includes('text/html') ? 0 : 1);
    });
    req.on('timeout', () => { req.destroy(); process.exit(1); });
    req.on('error', () => process.exit(1));
    req.end();
  " "$1" 2>/dev/null
}

# 先查项目配置端口（用户明写的，直接信）
if port_in_use "$FirstPort"; then echo "$FirstPort"; exit 0; fi

# 再扫常见备选端口 —— 这些是猜的，必须验证确实在提供 HTML
for port in 5173 5174 5175 3000 3001 3002 3003 3004 3005 8080 8081; do
  [ "$port" = "$FirstPort" ] && continue
  if port_in_use "$port" && serves_html "$port"; then
    # stdout 只给端口号（保持调用契约）；警告走 stderr。
    # HTML 校验挡得住后端 API / 数据库，但挡不住 nginx 这类也返回 HTML 的生产服务——
    # 所以扫出来的端口只可用于"打开看看"，**不要拿它去 close-server**（那可能关掉别人的服务）。
    echo "⚠ 端口 $port 是扫出来的，不在项目配置里。它未必是本项目的 dev server（nginx/别的项目也可能占着）。" >&2
    echo "  只用它打开页面；收尾时别关它——除非确认是你自己为这次验证启动的。" >&2
    echo "$port"
    exit 0
  fi
done

echo ""
exit 1
