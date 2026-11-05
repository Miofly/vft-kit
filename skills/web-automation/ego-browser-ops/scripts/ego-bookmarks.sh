#!/usr/bin/env bash
# 管理 ego lite 指定 profile 的书签：在该 profile 的临时 task space 打开 chrome://bookmarks，
# 调页内 chrome.bookmarks API（与书签管理器同一通道，浏览器运行中也安全；直接改 Bookmarks 文件会被运行中的浏览器覆盖）。
#
# 用法：ego-bookmarks.sh <profile名或id> <命令> [参数...]
#   tree [文件夹]                      列出全部（或某文件夹下）书签：id、路径、url
#   ls [文件夹]                        只列一层子项
#   search <关键词>                    按标题/url 搜索
#   add <文件夹> <标题> <url>          新增书签（文件夹不存在自动逐级创建）
#   mkdir <文件夹>                     逐级创建文件夹
#   mv <id> <目标文件夹> [index]       移动
#   rename <id> <新标题> [新url]       改标题/url
#   rm <id>...                         删除（文件夹连同子项），先打印被删内容
#   export <绝对路径.json>             导出整棵树备份
# 文件夹写法：数字 id，或按标题的路径，如 "书签栏/AI/tools"（根：书签栏、其他书签，也认 bar/other）。
set -euo pipefail
[ $# -ge 2 ] || { sed -n '4,15p' "$0"; exit 2; }
ARGS=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1:],ensure_ascii=False))' "$@")
# ego nodejs 的 console.log 走 stderr：结果写临时文件再 cat 到 stdout，方便管道解析
OUT=$(mktemp -t ego-bookmarks); trap 'rm -f "$OUT"' EXIT

ego-browser nodejs <<EOF
const [profile, cmd, ...args] = ${ARGS};
if (["search", "add", "mkdir", "mv", "rename", "rm", "export"].includes(cmd) && !args[0]) throw new Error(cmd + " 缺参数");
const p = (await profiles()).find((x) => x.name === profile || x.id === profile);
if (!p) throw new Error("profile 不存在: " + profile + "；可选: " + (await profiles()).map((x) => x.name).join(","));
const task = await taskSpace("ego-bookmarks " + p.id, { profileId: p.id });
try {
  const page = task.page("p1");
  if (!(await page.url()).startsWith("chrome://bookmarks")) await page.goto("chrome://bookmarks/");
  const out = await page.evaluate(async ({ cmd, args }) => {
    const B = chrome.bookmarks;
    const roots = (await B.getTree())[0].children;
    const alias = { bar: roots[0].id, other: roots[1]?.id };
    const pathOf = async (id) => {
      const parts = [];
      for (let n = (await B.get(id))[0]; n && n.id !== "0"; n = n.parentId ? (await B.get(n.parentId))[0] : null) parts.unshift(n.title);
      return parts.join("/");
    };
    const folder = async (spec, create) => {
      if (!spec) return roots[0].id;
      if (/^\d+$/.test(spec)) return spec;
      const [head, ...rest] = spec.split("/").filter(Boolean);
      let id = alias[head] || roots.find((r) => r.title === head)?.id;
      if (!id) throw new Error("根文件夹不存在: " + head);
      for (const t of rest) {
        const hit = (await B.getChildren(id)).find((c) => !c.url && c.title === t);
        if (hit) id = hit.id;
        else if (create) id = (await B.create({ parentId: id, title: t })).id;
        else throw new Error("文件夹不存在: " + spec);
      }
      return id;
    };
    const flat = (n, prefix, acc = []) => {
      for (const c of n.children || []) {
        const path = prefix ? prefix + "/" + c.title : c.title;
        acc.push({ id: c.id, path, url: c.url });
        flat(c, path, acc);
      }
      return acc;
    };
    switch (cmd) {
      case "tree": { const id = await folder(args[0]); return flat((await B.getSubTree(id))[0], await pathOf(id)); }
      case "ls": { const id = await folder(args[0]); return (await B.getChildren(id)).map((c) => ({ id: c.id, title: c.title, url: c.url })); }
      case "search": return Promise.all((await B.search(args[0])).map(async (c) => ({ id: c.id, path: await pathOf(c.id), url: c.url })));
      case "add": { const n = await B.create({ parentId: await folder(args[0], true), title: args[1], url: args[2] }); return { id: n.id, path: await pathOf(n.id), url: n.url }; }
      case "mkdir": { const id = await folder(args[0], true); return { id, path: await pathOf(id) }; }
      case "mv": { const dest = { parentId: await folder(args[1]) }; if (args[2] !== undefined) dest.index = Number(args[2]); await B.move(args[0], dest); return { id: args[0], path: await pathOf(args[0]) }; }
      case "rename": { const ch = { title: args[1] }; if (args[2]) ch.url = args[2]; const n = await B.update(args[0], ch); return { id: n.id, path: await pathOf(n.id), url: n.url }; }
      case "rm": {
        const gone = [];
        for (const id of args) { const sub = (await B.getSubTree(id))[0]; gone.push({ id, path: await pathOf(id), url: sub.url, children: flat(sub, "").length }); await B.removeTree(id); }
        return { removed: gone };
      }
      case "export": return B.getTree();
      default: throw new Error("未知命令: " + cmd);
    }
  }, { cmd, args });
  const fs = await import("node:fs/promises");
  if (cmd === "export") await fs.writeFile(args[0], JSON.stringify(out, null, 1));
  await fs.writeFile("${OUT}", JSON.stringify(cmd === "export" ? { exported: args[0] } : out, null, 1));
} finally {
  await task.finish({ keep: [] });
}
EOF
cat "$OUT"; echo
