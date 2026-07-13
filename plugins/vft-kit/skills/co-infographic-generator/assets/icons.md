# 常用线性图标（lucide 风格）

用法：把下面的内部内容塞进统一外壳里——
`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"> ...paths... </svg>`

需要别的图标时去 https://lucide.dev 搜，复制其 `<path>` 即可。保持 `fill="none" stroke="currentColor"`，颜色由 `.ico{color:var(--accent)}` 控制。

| 含义 | 内部 path |
|------|-----------|
| 文档 / 规格 | `<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 13h6M9 17h4"/>` |
| 对勾 / 验证 | `<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>` |
| 盾牌 / 质量 | `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/>` |
| 模块 / 网格 | `<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>` |
| 协作 / 多人 | `<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>` |
| 循环 / 迭代 | `<path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>` |
| 闪电 / 性能 | `<path d="M13 2 3 14h7l-1 8 10-12h-7z"/>` |
| 代码 / 迁移 | `<polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/>` |
| 层叠 / 技术栈 | `<path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 12l9 5 9-5"/><path d="M3 17l9 5 9-5"/>` |
| 立方 / 标准化 | `<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="m3.3 7 8.7 5 8.7-5M12 22V12"/>` |
| 搜索 / 分析 | `<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>` |
| 增长 / 效率 | `<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>` |
| 灯泡 / 方案 | `<path d="M12 2a5 5 0 0 1 5 5c0 2-1 3-1 5h-8c0-2-1-3-1-5a5 5 0 0 1 5-5z"/><path d="M9 17h6"/><path d="M10 21h4"/>` |
| 编辑 / 优化 | `<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/>` |
