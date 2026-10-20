# zh-humanizer 评测

## 题目
- `cases.jsonl`：32 条，每行 `{id, request, source}`。B-xx 是 shuorenhua v2.5 冻结核心集（27 条，含 10 条正常文本，MIT，来源 https://github.com/MrGeDiao/shuorenhua/tree/main/evals/v2.5），W-01～W-05 是人人都是产品经理风格自编题。
- `holdout.jsonl` / `holdout-meta.jsonl`：20 道留出题（shuorenhua 非核心题随机抽，正常文本 10 + 需清理 10），只用来验证，不据此改规则。
- `cases-meta.jsonl`：每题是否为正常文本（normal）、是否属于正向收益集（positive）。只给判官，不给改写模型。
- `criteria.md`：shuorenhua v2.5 编辑质量判据，只给判官。

## 跑法（三个独立模型角色）
1. 改写：两个改写模型分别只读 `../references/edit-rules.md`（新规则）或 `simple-prompt.md`（基线）加 `cases.jsonl` 与 `holdout.jsonl`，各写 `out-<方案>.jsonl`，每行 `{id, output}`。不得读取判据和 meta。
2. 判官：读 `criteria.md`、`cases.jsonl`、`cases-meta.jsonl` 和两份输出（每题随机标成 A/B，映射另存），每题给两方 fidelity / task（pass/fail/review）和 quality（better/same/worse/review），fail 必须引用原文与输出片段；再给 A/B 偏好。
3. 主控复核所有 fail 与 review，抽查判官判 pass 的题，汇总写 `results-<日期>.md`。

## 通过线（沿用 shuorenhua v2.5）
- 硬失败（fidelity/task fail）为零。
- 正常文本误改率（worse 或 fail 的题数 / 正常文本题数）< 10%。
- positive 集至少 5/7（加自编 W 题另算）达到 better，其余不 worse。
- 新规则对基线的盲比胜/平/负单列报告；新规则没有额外收益时，缩规则而不是加规则。
