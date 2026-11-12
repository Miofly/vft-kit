# 正文检查、格式分支与最终交付

## 可运行的离线工具

`SKILL_DIR`、`PAPER_PATH`、`BIB_PATH`、`LEDGER_PATH` 和 `ATTESTATIONS_PATH` 均设置为实际绝对路径。所有检查器只读输入、输出 JSON，退出 0=该检查范围无阻断，1=有阻断，2=输入非法；不用输出中的 ok 代替学术质量结论。

```bash
# Markdown/文本/DOCX 的数字引文、图像和匿名候选检查
python3 -B -I "$SKILL_DIR/scripts/check_manuscript.py" "$PAPER_PATH"
# LaTeX 常见 cite 命令、BibTeX 和标签；多个库重复 --bib
python3 -B -I "$SKILL_DIR/scripts/check_manuscript.py" "$PAPER_PATH" --bib "$BIB_PATH"
# 必要时添加 --anonymous-term "需匿名的具体名称"，可重复
# 统一记录 + 正文 + 六层实际人工复核
python3 -B -I "$SKILL_DIR/scripts/check_delivery.py" "$PAPER_PATH" "$LEDGER_PATH" --attestations "$ATTESTATIONS_PATH"
# TeX 总交付也可加 --bib "$BIB_PATH"
```

引用解析直接复用 quzhiii/thesis-skills 固定版本的四个模块，原许可与修改声明在 scripts/vendor/。本地包装负责 Markdown/Word、输入限制、状态和 CLI，不运行上游全部流水线。

## 覆盖与不覆盖

- Markdown/TXT/DOCX：识别独立“参考文献/References”标题及 `[1]` 编号，比较正文数字引文与文后表，提示未引用条目，阻断重复编号及找不到文后条目的引用。Markdown 代码块和常见链接排除；数字区间、图片占位、缺失/空图片也检查。
- TeX：识别常见 cite/citep/citet/parencite/textcite/autocite，核对显式提供的 BibTeX；检查重复 key/DOI、常见元数据缺项和 label/ref。不会递归读取 input、执行宏或编译；外部资源和自定义引用宏需要真实工具链另验。
- DOCX：限制压缩包总展开大小、检查 CRC 和 XML，提取主文档段落，提示批注/修订。不会写回、解压执行或运行宏。表格中的段落可提取，但字体、分页、脚注、页眉、Zotero/EndNote 域、图片布局和全部元数据匿名化不在覆盖内。
- 作者—年份引用、复杂 BibTeX 表达式、手写上标、跨文件 TeX、扫描/OCR 等不能冒充已经支持。输出 citation_check=not_covered 或 warnings 后，补人工或已有专用工具核对。
- 匿名词表检查只覆盖所读正文，不能证明 ZIP 元数据、图内文字、批注、文件名或 PDF 元数据没有身份信息。远程图只提示未验证，不发起网络请求。

## 研究与内容分支

- 教育/人文：先材料和问题，再理论与设计；不套计算机系统实现或机器学习实验结构。
- 工程系统：从真实源码、数据库结构、接口、测试、截图提取证据；功能存在、测试通过与用户业务完成分别记录，不把演示截图当压力/安全验证。ER/流程图从实际结构生成，图表编号与正文对应。
- 实证/ML：贡献必须有适当比较、基线、消融或适合该问题的证据；说明数据来源、划分、泄漏风险、随机性和局限，没做的实验列未来工作。统计检验取决于设计，不能为追求完整编结果。
- 理论/建模：列假设、变量与单位、推导、边界条件、验证和敏感性；有数据才作拟合/回测，不把模拟当实测。赛事模板只在用户确属该赛事且核实当届规则后采用，匿名与 AI 披露按当届要求。

## Word/LaTeX 与 PDF 交付

优先用学校正式模板和已有 office-doc-rewrite/渲染工具；不擅自换 LaTeX、安装重型软件或生成“类似模板”。只在副本上修改，保留图表、合并单元格、公式、交叉引用、目录和编号。

TeX 先检查源码中可能执行命令、外部输入和 shell-escape；陌生项目不直接跑 latexmkrc、Makefile、安装器或用户输入的代码。确认源码安全、工具已安装且任务需要后再在独立产物目录编译，保持 shell-escape 关闭；未编译则明确未验证。

最终文件逐页确认封面、目录、摘要、图表、公式、页码、参考文献及页末溢出；检查 undefined citation/reference、字体缺字、分页和图像清晰度。已有 PDF 工具可核对页数/大小/文本层，但页数和非空文本不证明视觉正确。Word→LaTeX 或 DOCX→PDF 迁移要回核正文、公式、表格、引用和图片数；不支持的结构显式列出，不以悄悄丢失换成功。

## 六层复核和总闸门

复制 [六层模板](../assets/delivery-attestations.json) 到用户论文工作区，只有实际完成才改 passed 并写核对位置；确实不适用写 not_applicable 并说明依据，不是跳过理由。六层为 evidence/citations/methods/format/rendering/privacy。

总检查器组合证据记录、正文预检和六层声明。draft 可保留待核验警告；final 有待完成层或阻断问题则失败。人工声明本身可能不真实，程序无法识别，所以最终批准仍归作者。读不到来源、无原始数据、没打开最终文档，不能改状态骗过门槛。

## 审稿与重审

按统一流程四视角检查，输出总体判断、论证主线、逐章问题、优先级、具体修改位置。重审先核对旧问题是否实际修复，再查修订是否制造新矛盾；不能只重读作者回复。

每个严重问题附原文与来源定位，区分可证明错误、疑点和学科判断；对尚无领域校准的模型评分不报客观分数或通过率。存在证据分歧时记录不同解释，不能以投票或“多专家一致”盖过事实。限制耗时按真实证据缺口停止，不把可继续修改的章节丢回用户。

## 一键回归

```bash
python3 -B -I "$SKILL_DIR/scripts/run_tests.py" --temp-dir "$TEST_TEMP_DIR"
```

`TEST_TEMP_DIR` 是用户指定或宿主约定的绝对临时产物目录。测试使用本地合成文件，覆盖正反样本和 CLI 只读行为；不证明真实论文质量、数据库检索覆盖、字体版式或模型触发率。
