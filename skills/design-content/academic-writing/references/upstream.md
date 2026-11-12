# 上游来源与继承边界

核对日期：2026-11-12。

## 选型

主线采用 [K-Dense-AI/scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills)，MIT；固定 commit：`2d2065fb4520fa3f3f2bcf61cff26ec8b7eba4b5`。旧名 claude-scientific-skills 重定向到该仓库，不能当成两个独立候选。

后续补查 9 个仓库，比较与固定版本见 [多来源选型](source-comparison.md)。新增采纳 humanities-thesis-skill、Chinese Thesis Workbench 与 Orchestra ML Paper Writing 的材料论证、模板/图表追溯和贡献表达；原文与 MIT 许可也已保留。K-Dense 仍负责证据与写作主流程，其他来源按需补充，不叠加多个互相覆盖的入口。选型是内容范围判断，未做效果排名或独立对照评测。

## 保留的原文

以下快照为上游原始字节，保留其中 frontmatter，仅改文件名以避免嵌套 SKILL.md 被宿主当成独立技能：

- [scientific-writing 原文](upstream/scientific-writing.md)：上游 `skills/scientific-writing/SKILL.md`，内部标记版本 2.3。
- [literature-review 原文](upstream/literature-review.md)：上游 `skills/literature-review/SKILL.md`。
- [citation-management 原文](upstream/citation-management.md)：上游 `skills/citation-management/SKILL.md`。
- [原始 MIT 许可](upstream/LICENSE.md)：Copyright (c) 2025 K-Dense Inc.

这些快照是来源证据，不是第二套执行入口。其 links、scripts、assets 指向完整上游仓库，本地未打包的路径不能执行；需要扩展能力时先查固定 commit 原文及依赖，不能按快照中的相对路径跨出本技能。

## 采纳与改编

| 上游机制 | vft-kit 落地 |
|---|---|
| evidence outline、证据绑定、保留不确定性 | 每节先建立论点—来源—缺口，摘要与结论不得新增事实 |
| 写作、核验与最终批准分离 | 输出状态区分草稿、待核实、未实施；作者控制最终学术判断 |
| 方法与结果协调、表图一致性 | 交付前核对数据、样本、单位、方向与因果措辞 |
| 文献综述七阶段 | 选题范围、检索、筛选、提取、综合、引用核验与交付；普通综述不伪装系统综述 |
| 多数据库发现、元数据抽取、引文核验 | 复用宿主已有检索工具，中文教育研究补中文数据库和官方政策 |
| 保密、作者责任与披露 | 未公开稿件和学生资料不默认外传，AI 使用按学校/期刊实际要求披露 |

中文毕业论文模板、旧 `.doc` 读取、教育干预/作业设计、PDF 下载核验是本地补充；不把某所学校要求或某个论文题目固化为通用默认。

## 不照搬

不批量安装上游全部技能、Python 依赖或商业工具；不要求付费 API、OpenRouter、parallel-cli 或商业写作服务，不自动推荐或上传至任何服务。不复制完整上游工具链和机构专属模板；检索与排版依靠宿主已有工具，离线工具统一见 [正文与交付](manuscript-and-delivery.md)。`check_evidence.py`、`check_delivery.py` 和 Markdown/DOCX 包装为本地实现；TeX/BibTeX 四个解析模块实际复用 quzhiii/thesis-skills 固定版本，原 MIT 许可与仅改包内导入的说明保存在 scripts/vendor/。不冒称其完整联网、生成、编译和修复流水线已迁入。统一流程、阶段衔接与顺序评审见 [混合流程](workflow-and-review.md)。

不把“按清单检查”当作学术质量评分或投稿保证。不强制所有学科 IMRaD、系统综述或元分析，不承诺降低查重率、通过 AI 检测或替代真实研究。当前验证不包含独立模型 A/B 或写作质量提升结论。
