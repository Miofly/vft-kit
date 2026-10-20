---
name: zh-humanizer
description: "中文去 AI 味、去套话，改成真人口吻（周报、简历、文案、README、公众号、投稿），保留数字与事实；也可用作者亲历素材写文章。触发：AI 味、说人话、改自然点、降 AI 率、模板腔、只标问题不改写、被退稿纯AI生成。不用于翻译、查错字、仿写、起标题、AI 检测。"
---

# 中文去 AI 味与拟人化

五个开源 skill 合成一套，分两个阶段用，不混用：

| 阶段 | 用什么 | 什么时候 |
|---|---|---|
| 写稿 | [references/write-craft.md](references/write-craft.md) | 从素材写新稿 |
| 改稿 | [references/edit-rules.md](references/edit-rules.md) | 已有成稿，去 AI 味 |

改稿阶段不引入写稿手法（不加口语词、感受、经历），写稿阶段的产物最后仍要过一遍改稿规则。

## 先说边界

- 平台退稿写“纯AI生成，请补充个人观点”时，缺的是作者本人的经历和判断。本 skill 只能让文字自然，不能替作者编观点；先向作者要素材，再写。
- 不判断文本是不是 AI 写的，不保证通过任何检测器，不用于把纯 AI 稿伪装成人写的去绕过平台规则。
- 信息守恒优先于一切风格要求：数字、事实、限定词、作者立场一个都不能变。

## 改稿流程

1. 锁定原稿：记下人、事、数、时间、引语、归因、限定、排除关系。
2. 按 edit-rules.md 的 39 条逐句检查，只改命中的部分，最小改动；第五节列出的特征（句长、问句、比喻、被动句等）不作为改写理由。
3. 默认不动结构（标题层级、段落数与顺序）。用户明确说“可以重写结构/大改”时，才允许合并、拆分、调序段落，且独立事实、例子、反例一个不丢。
4. 对照第 1 步的清单复查；任何新增实词指不出原稿出处就撤销。
5. 只交改好的全文。用户要“只标问题”时，引用问题片段并说明改法，不交全文。

改前保留一份原稿（如 `xxx.v1.md`），方便用户对比。

## 写稿流程

1. 向作者确认素材：亲历的事、当时的判断、真实数据。没有就列问题给作者，不在正文留“待补”占位，也不写资料说明、署名之类的尾巴。
2. 按 write-craft.md 写。
3. 写完按 edit-rules.md 逐条复查一遍成稿再交付，尤其是破折号、“不是……而是”对举、序号小标题和套话收尾；这一步省掉，写稿手法本身就会带进新的 AI 腔。
4. 交付时把第 1 步的问题列在文章前面，文中凡是推测都写成推测口气。
5. 再列出正文里所有以“我”为主语、但素材里找不到出处的句子，请作者逐句确认或删除。实测模型最常在这里替作者编动机、感受和“我实测过”。

## 接入下游系统

需要把规则拼进其他系统（如文章生成流水线）的提示词时，只引用 references 里的三个源文件：edit-rules.md（改稿）、write-rules-compact.md（写稿阶段精简版，约 1k 字）、banned-patterns.txt（成稿校验清单）。下游同步脚本放在各自的私有层，规则只改本 skill 的源文件，再同步过去。

## 评测

`evals/` 下有冻结评测：核心 32 题（shuorenhua v2.5 冻结核心 27 题，含 10 条正常文本测误改，加 5 条人人都是产品经理风格自编题）和 20 道留出题（不参与调规则，防过拟合）。改写模型只读规则和题目，判官另读判据，新规则与简单提示词匿名盲比。2026-10-10 共 8 轮、Claude 与 Codex 两家判官盲评，结果见 `evals/results-2026-10-10.md`：最终版两家判官都判保真零失败、正常文本零误改，简单提示同批 13–16 题丢信息。改 edit-rules.md 后先跑 `python3 scripts/check-contamination.py`（规则举例句和题目撞车会让分数虚高，退出码 1 即有泄漏），再按 `evals/README.md` 重跑。

`evals/evals.json` 是 skill-creator 格式的 3 个整体任务（改段落、改周报不动结构、写新稿），用于对比有无本 skill 的表现。

## 来源（均为 MIT，许可全文见 [LICENSES.md](LICENSES.md)）

- [MrGeDiao/shuorenhua](https://github.com/MrGeDiao/shuorenhua)：保真边界、只标问题模式
- [larashero3-dotcom/lieflat-less-ai-tone](https://github.com/larashero3-dotcom/lieflat-less-ai-tone)：基于 283 万字语料的 11 条可定位规则与“不作为改写理由”清单
- [op7418/humanizer-zh](https://github.com/op7418/humanizer-zh)：31 种模式与编辑优先级
- [LifelongLazyLearner/qu-ai-wei](https://github.com/LifelongLazyLearner/qu-ai-wei)：语义硬边界、推论台阶、同义轮换、结构重写授权
- [KKKKhazix/khazix-skills](https://github.com/KKKKhazix/khazix-skills) 的 khazix-writer：写稿手法（已去掉个人化内容）

