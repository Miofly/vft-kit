# 论文技能多来源选型

核对日期：2026-11-12。继首轮 K-Dense 后补查 9 个仓库；读取其中 8 个的相关 SKILL.md，以及 1 个工具项目的 README 做范围核对。候选存在不等于独立原创；星数、搜索排名和仓库自述不能证明写作效果。后续已直接复用 quzhiii 的四个离线解析模块并运行本地包装及测试；没有执行候选的安装、发布、多 agent 或模型编排。

## 候选与适用范围

| 仓库 | 实际核对入口 | 可用之处 | 本地取舍 |
|---|---|---|---|
| [humanities-thesis-skill](https://github.com/ganzhi-black/humanities-thesis-skill) | 根 SKILL.md | 中文人文社科，从材料形成问题、理论适用性、章节递进 | 采纳论点与材料关系；教育研究仍以调查/实施证据为准 |
| [chinese-thesis-workbench-skill](https://github.com/ZyhSechub/chinese-thesis-workbench-skill) | 根 SKILL.md | 学校模板、项目证据、图表登记、章节/DOCX 交付 | 采纳要求与证据追溯、图表来源；不强制生成庞大工作台 |
| [Orchestra AI-Research-SKILLs](https://github.com/Orchestra-Research/AI-Research-SKILLs) | 20-ml-paper-writing/ml-paper-writing/SKILL.md | 英文 ML/AI 论文，明确贡献、证据主线、引用和会议交付 | 采纳问题—贡献—证据主线；不把会议模板用于教育毕业论文 |
| [quzhiii/thesis-skills](https://github.com/quzhiii/thesis-skills) | README.md、四个 citation_integrity 模块 | Word/LaTeX、引用完整性、readiness gate、确定性审计 | 已复用四个解析模块，接入正文/交付包装；未整包迁入联网核验与修复流水线 |
| [academic-research-skills](https://github.com/brycewang-stanford/academic-research-skills) | academic-paper-reviewer/SKILL.md、LICENSE | 多视角审稿、重审、校准模式 | 核实原许可为 CC BY-NC 4.0（Cheng-I Wu）；未复制受该许可约束的正文/代码，以本地顺序评审满足多视角、重审与不报未经校准分数的需求，不运行上游多 agent |
| [thesis-skill-hub](https://github.com/DQXCJ-a11y/thesis-skill-hub) | 根 SKILL.md | 硕士论文写作与审查聚合 | 全文总审需求已落为总体判断、主线、逐章问题、优先级与回修定位；不重复导入同源规则或分数承诺 |
| [thesis-creator](https://github.com/Stars-OC/thesis-creator) | 根 SKILL.md、document_exporter/preflight.py | 本科论文、图像、数据库/流程图和交付 | 图像占位/缺失/空文件预检需求已在本地实现，工程证据分支已接入；未复制上游 YAML/导出流水线，不允许待补图冒充定稿，不采纳降 AIGC/降重承诺 |
| [mathmodel-latex-skill](https://github.com/wangling-miao/mathmodel-latex-skill) | 根 SKILL.md | MCM/ICM/CUMCM LaTeX 模板、引用/匿名/PDF 预检 | 建模、当届规则/匿名/AI披露与真实编译验收需求已落入交付分支；通用标签与引用检查复用有MIT许可的 quzhiii 模块，不复制未确认许可的赛事模板或脚本 |
| [Oh-my--paper](https://github.com/LigphiDonk/Oh-my--paper) | skills/ml-paper-writing/SKILL.md | 论文工作台，整合 ML 与 scientific-writing 等技能 | 所读 ML 上游指令段与 Orchestra 主线重合，已通过原始来源覆盖；保留一入口按阶段路由，不重复打包GUI、模型编排或同源技能 |

对当前中文教育论文优先采用前三项中有用的机制；保留一个 academic-writing 入口，按任务加载参考，不把多个互相覆盖的技能全部加入常驻描述。

## 固定版本

| 仓库 | commit |
|---|---|
| ganzhi-black/humanities-thesis-skill | `9f9c97162e250df8d6c214b828bb973828a2a780` |
| ZyhSechub/chinese-thesis-workbench-skill | `1dac3f89b293a5827a0bf5fc538dcd3a184cead8` |
| Orchestra-Research/AI-Research-SKILLs | `773a52944ba4747a18bd4ae9ade53fff041adcbc` |
| quzhiii/thesis-skills | `e15ccc5b5208260b1eb77f1e9dfc1868a54bf9eb` |
| brycewang-stanford/academic-research-skills | `c22c17eed8a5753aa60681be9734919f2e2f5b42` |
| DQXCJ-a11y/thesis-skill-hub | `0947beb624fa3aa70b4524343e660e5d8abbdd03` |
| Stars-OC/thesis-creator | `edf95dfe9c7a2fe3fa6aa791d0ed5d45802b6f26` |
| wangling-miao/mathmodel-latex-skill | `bc2d1a69660ebe48438c288cd608fad75776f825` |
| LigphiDonk/Oh-my--paper | `6baece9f13324c209592124ebc213289336f26c3` |

## 已采纳原文与许可

三项补充均核对 MIT，原文按固定 commit 保存：

- [humanities-thesis](upstream/humanities-thesis.md)、[原许可](upstream/humanities-thesis-LICENSE.md)。版权行原样为 Copyright (c) 2025-2026。
- [Chinese Thesis Workbench](upstream/chinese-thesis-workbench.md)、[原许可](upstream/chinese-thesis-workbench-LICENSE.md)。Copyright (c) 2026 Zyhsec。
- [Orchestra ML Paper Writing](upstream/ml-paper-writing.md)、[原许可](upstream/ml-paper-writing-LICENSE.md)。Copyright (c) 2025 Claude AI Research Skills Contributors。

这些文件是来源快照，不是第二套执行入口。未经迁入的脚本、路径、模板与上游推荐服务不能直接执行。学术行为以本地 SKILL.md 及其适用参考为准；不继承任何检测规避、保证录用或替代真实研究的承诺。

## 证据强度

已核对实际文本、仓库身份、固定版本与直接复用项目许可；四个解析模块及本地包装已通过合成文件和CLI回归。没有安装候选完整工具链、编译真实赛事论文或生成整篇论文做盲测，也没有运行独立模型 A/B。这里的“适用”是内容范围判断，不是效果实测排名。

补查9项均已逐项处理：前三项进入主写作流程，quzhiii提供解析代码，评审/聚合/导出/建模候选的适用需求进入本地评审与交付分支，Oh-my--paper去重到原来源。覆盖需求不等于搬入每个项目的全部功能、脚本、模板和GUI；仍不宣称全量兼容。
