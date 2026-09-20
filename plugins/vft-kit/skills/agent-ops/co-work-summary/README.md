# co-work-summary

基于本机 Claude Code、Codex、Gemini 编码会话与 Git 提交生成指定时间段的开发工作总结。

## 1. 运行约束

- 运行时只读取本机数据，只向终端输出。
- 不创建或修改任何文件。
- 每个 Git 仓库使用自己的 `user.email` 或 `user.name` 识别本人提交。
- 默认扫描用户主目录；外部仓库根目录可通过参数补充。
- 采集异常会出现在 D. 采集提示，不会被伪装成无工作记录。

## 2. 组成

- `SKILL.md`：时间解析、采集、归纳与输出规则。
- `scripts/collect.py`：只读采集三类 AI 会话和 Git 提交。
- `tests/test_collect.py`：日期、解析、仓库发现、Git 身份和输出回归测试。
- `evals/evals.json`：技能触发与输出评测用例。

## 3. 手动调试

```bash
python3 /absolute/path/to/co-work-summary/scripts/collect.py
python3 /absolute/path/to/co-work-summary/scripts/collect.py --start 2026-08-03 --end 2026-08-07
python3 /absolute/path/to/co-work-summary/scripts/collect.py --start 2026-07-20 --end 2026-07-26
python3 /absolute/path/to/co-work-summary/scripts/collect.py --repo-root /Volumes/work
```

运行测试：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```
