#!/usr/bin/env bash
# 关闭**本 skill 自己启动的**前端 dev server。
#
# 用法:
#   close-server.sh <端口...>    关掉指定端口（正常用法：传第 1 步探测到的那个端口）
#   close-server.sh              只列出常见端口上在跑的前端服务，**不杀**
#   close-server.sh --all        真的去杀常见端口上的所有前端服务（危险，见下）
#
# 为什么不传端口就不杀：脚本没法区分「这次验证是我起的服务」和「用户本来就开着的服务」。
# 闭环的规矩是"用户原本就开着的别关"，而盲扫 5173/3000/8080… 一路 kill 过去，
# 大概率会顺手杀掉用户另一个终端里正在跑的项目。所以默认只报告，让调用方拿着端口来杀。

set -uo pipefail

COMMON_PORTS=(5173 5174 5175 3000 3001 3002 3003 3004 3005 8080 8081)

FORCE_ALL=0
PORTS=()
for a in "$@"; do
  case "$a" in
    --all) FORCE_ALL=1 ;;
    *) PORTS+=("$a") ;;
  esac
done

pids_on() {
  command -v lsof >/dev/null 2>&1 || return 0
  lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null
}

# —— 无端口且没有 --all：只报告，不动手 ——
if [ "${#PORTS[@]}" -eq 0 ] && [ "$FORCE_ALL" -eq 0 ]; then
  found=0
  for port in "${COMMON_PORTS[@]}"; do
    pids="$(pids_on "$port")"
    [ -z "$pids" ] && continue
    found=1
    for pid in $pids; do
      cmd="$(ps -o comm= -p "$pid" 2>/dev/null | tail -c 40)"
      echo "  :$port  PID $pid  ${cmd:-?}"
    done
  done
  if [ "$found" -eq 0 ]; then
    echo "常见前端端口上没有在跑的服务。"
    exit 0
  fi
  echo ""
  echo "没有传端口，所以只列出、不关闭——分不清哪个是本次验证起的、哪个是你自己开着的。"
  echo "要关就带上端口: close-server.sh <端口>   （确实想关掉上面全部: close-server.sh --all）"
  exit 0
fi

[ "$FORCE_ALL" -eq 1 ] && [ "${#PORTS[@]}" -eq 0 ] && PORTS=("${COMMON_PORTS[@]}")

closed=0
for port in "${PORTS[@]}"; do
  pids="$(pids_on "$port")"
  [ -z "$pids" ] && continue
  for pid in $pids; do
    [ "$pid" = "0" ] && continue
    if kill "$pid" 2>/dev/null; then
      echo "已关闭端口 $port 上的服务 (PID: $pid)"
      closed=$((closed + 1))
    fi
  done
done

if [ "$closed" -eq 0 ]; then
  echo "指定端口上没有发现运行中的服务"
  exit 1
fi
exit 0
