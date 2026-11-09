# Awesome-REA：六领域资源、案例与论文

本目录是 [reacher-z/Awesome-REA](https://github.com/reacher-z/Awesome-REA) 的精选本地快照，供 `rea` 离线检索。它是独立资源集合，不是 `morluto/rea` 官方生态仓库、另一套引擎或本机运行成绩。

## 来源与版本

- 分支 `main`，固定提交 `557f77392f83c6d2932f4522324a7588048d33e6`，快照日期 `2026-11-09`。
- 10 个文件，10,178,089 字节；数量与字节仅统计 `upstream/` 原文。
- 原文与代码采用 [MIT 许可](upstream/LICENSE)；链接项目各自保留原许可。本快照未收录链接项目源码。
- [SHA256SUMS](SHA256SUMS) 覆盖全部原始文件，相对于本目录；未改原文字节或路径。原文未随附的相对链接回固定提交的上游查看。

## 收录范围（精选，非全仓）

| 原文件 | 内容 |
| --- | --- |
| [LICENSE](upstream/LICENSE) | 上游 MIT 原文 |
| [data/rea-resources.json](upstream/data/rea-resources.json) | 178 条 REA 相关案例、集成、文档等 |
| [data/tool-resources.json](upstream/data/tool-resources.json) | 2,670 条独立工具、案例、集成等；不全是工具 |
| [data/papers.json](upstream/data/papers.json) | 235 篇论文，`kind=research` |
| [data/evidence-classes.json](upstream/data/evidence-classes.json) | 2,848 条精选资源的公开证据档位与运行状态 |
| [data/README.md](upstream/data/README.md) | 字段、词汇与审核规则 |
| [证据档位](upstream/docs/evidence-classes.zh-CN.md) | C0–C3 / Unknown v4 Beta |
| [产物可用性](upstream/docs/artifact-evidence.zh-CN.md) | 分开源码、下载、演示、许可与运行证明 |
| [REA 生态](upstream/docs/rea-ecosystem.zh-CN.md) | REA 关系与生态说明 |
| [工具图谱](upstream/docs/tool-landscape.zh-CN.md) | 独立工具的能力边界 |

未搬入：网站构建系统、自动发现历史、`source-index` 未审查仓库扫描、贡献者指令和 C0 人工复核明细。追查某个 C0 时回上游 `data/evidence-class-zero-reviews.json` 找人工记录；收录一个档位字段不能替代原始复核证据。

## 如何查找

先用已有工具；缺能力时按六领域 `website / game / app / binary / firmware / protocol` 和 kind 查询，最多读 2–3 个候选的 prerequisites、限制与一手 evidence URL。完整方法见[资源选择与验收](../resource-selection.md)。

- 工具与集成：两份 resource 列表均可含候选，按 `kind=tool / integration / project` 筛，不按文件名猜类别。
- 案例：两份列表都有 `kind=case-study`；核对目标版本、full/partial 范围和真实复现材料。
- 论文：`kind=research` 包括论文及少量研究资源；识别是否带 `title/year/venue`，阅读 `scope_limitations_*`，不把论文样本效果外推到整程序。

将 `REA_SKILL_DIR` 设为本 skill 的绝对路径：

```bash
python3 "$REA_SKILL_DIR/scripts/search-awesome-rea.py" \
  --skill-dir "$REA_SKILL_DIR" --query ghidra --target binary --kind tool --limit 3 --json
python3 "$REA_SKILL_DIR/scripts/search-awesome-rea.py" \
  --skill-dir "$REA_SKILL_DIR" --target app --kind case-study --limit 5
python3 "$REA_SKILL_DIR/scripts/search-awesome-rea.py" \
  --skill-dir "$REA_SKILL_DIR" --query decompile --kind research --limit 5 --json
```

搜索只读固定 JSON，不联网、不写缓存、不启动 provider/setup。`--query`、`--target`、`--kind` 至少给一个；`--limit` 是正整数。JSON 保留来源文件、核验日期、scope、上游审核状态和运行边界；重复资源或证据 id、畸形证据结构明确报错，不静默覆盖。`--kind research` 当前匹配 245 项：235 篇论文与 10 项研究资源，不等同于仅论文筛选。没有匹配不等于目录外不存在方案。

## 官方关系与验证边界

`relationship` 描述资源与 REA 的关系，不表示本集合隶属 REA：`official-core / official-skill / official-documentation / official-guide / official-case-study` 指 REA 官方材料；`community-*`、`independent-*`、`foundation`、`learning` 与 `upstream-maintainer-companion-list` 各有独立来源，按原条目核对。对任务适用比“官方优先”更重要，不把集成认成已连接的内建工具。

3,083 条资源/论文的 `verification=source-reviewed` 是上游审核文档/源码的状态，**不是本机执行记录**。2,848 条精选资源的档位表 `runtime_status=not-run`，不能改成本机成功，也不能外推为“作者从未运行过”。

C0 是人工确认的完整软件复现，C1 是有 download + 非品牌 demo 的自动上限（或非复现项目），C2 缺 download/demo 但有 code/docs，C3 缺 code/docs，Unknown 是上游复核时来源不可读。`scope`、`evidence_status` 与运行状态分开；档位不保证依赖可装、当前链接可达、安全性或方法有效。上游 README 的宣传计数有不同生成范围，以固定 JSON 实际计数为准。

## 更新与校验

先获取新的独立固定 checkout，对照改动与字段兼容性，再有意更新 10 文件、提交、总字节、清单、主入口、检索测试和博客；不自动 `git pull` 覆盖快照，不运行上游发布/扫描脚本。

```bash
python3 "$REA_SKILL_DIR/scripts/verify-reference-snapshots.py" --skill-dir "$REA_SKILL_DIR"
REA_TEST_DATA_DIR="$REA_SKILL_DIR/references/awesome-rea/upstream/data" \
  python3 "$REA_SKILL_DIR/scripts/test-search-awesome-rea.py"
```

完整性检查证明所选原文、目录结构与本地链接一致，不代表所有工具、案例或论文已复现。本次未逐条联网复核、安装依赖、执行目标或跑模型评测。
