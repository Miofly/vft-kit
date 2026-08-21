# diagram-design 集成参考

本文档说明 co-infographic-generator 如何与 diagram-design 协作。

## 工具职责划分

### diagram-design（优先）
**专长**：27 种标准化专业图表，自动品牌配色
- 技术图表：架构图、流程图、时序图、状态机、ER图、泳道图、树形图、高层架构、数据流图
- 业务分析：四象限、时间线、甘特图、循环图、金字塔/漏斗、韦恩图
- 导入重绘：draw.io、Mermaid

**特点**：
- ✅ 27 种预定义类型，标准化输出
- ✅ 60 秒品牌配置，自动匹配网站配色
- ✅ 输出独立 HTML，支持导出 PNG/SVG
- ✅ 4px 网格对齐，专业排版
- ✅ 无障碍支持（ARIA 标签）

**不适合**：
- ❌ 需要自由排版的信息图
- ❌ 需要特殊视觉效果（渐变、玻璃拟态、光晕）
- ❌ 27 种类型覆盖不了的自定义图表

### co-infographic-generator（本 skill）
**专长**：自由排版信息图，精确视觉设计
- 信息展示：KPI 看板、并列卡片、A/B 对比、成就展示
- 视觉效果：渐变质感、玻璃拟态、光晕效果、品牌定制排版
- 简单流程：线性步骤流程（无分支决策）

**特点**：
- ✅ HTML+CSS 像素级控制
- ✅ 5 种配色风格（科技青、暖金高端、靛紫品红等）
- ✅ 可自由组合组件（卡片、徽标、标签、进度条等）
- ✅ 中文渲染 100% 准确
- ✅ 可改可重渲

**不适合**：
- ❌ 标准化技术图表（架构、流程、时序等）→ 应该用 diagram-design
- ❌ 复杂分支流程 → 应该用 diagram-design 的 flowchart
- ❌ 组织架构 → 应该用 diagram-design 的 org-chart

### multi-chart-draw
**专长**：纯数据统计图表（ECharts）
- 柱状图、折线图、饼图、散点图
- 交互式图表（缩放、hover、图例筛选）
- 大数据量可视化

## 路由决策关键词

### → diagram-design
- **架构**：系统架构、技术架构、服务架构、微服务架构、组件架构
- **流程**：业务流程、审批流程、工作流、决策流程、处理流程
- **时序**：时序图、消息流、API 交互、调用链、通信流程
- **状态**：状态机、状态转换、生命周期、状态流转
- **ER/数据**：ER 图、数据模型、实体关系、表结构
- **泳道**：跨职能流程、多角色协作、分工流程
- **组织**：组织架构、团队结构、汇报关系、职能分工
- **四象限**：矩阵分析、定位分析、2×2 分析、优先级矩阵
- **时间线**：项目时间线、里程碑、发展历程、版本演进
- **甘特**：项目进度、任务排期、资源分配
- **循环**：飞轮、闭环、反馈循环、持续改进
- **金字塔/漏斗**：层级关系、转化漏斗、销售漏斗
- **韦恩**：集合关系、重叠分析、交集并集

### → co-infographic-generator（本 skill）
- **KPI**：KPI 看板、指标看板、数据大屏、成果展示
- **卡片**：并列卡片、要点卡片、特性展示、功能列表
- **对比**：A/B 对比、前后对比、方案比较、优劣对比
- **步骤**：简单步骤、线性流程（无分支）、操作指南
- **成就**：里程碑卡片、成就展示、荣誉展示

### → multi-chart-draw
- **统计**：柱状图、折线图、饼图、散点图
- **数据**：数据可视化、数据分析、趋势分析

## 检查 diagram-design 是否已安装

```bash
# 方法 1：检查插件目录
if [ -d "$HOME/.claude/plugins/cache/diagram-design" ]; then
  echo "diagram-design 已安装（via 插件目录）"
fi

# 方法 2：检查 installed_plugins.json
node -e "
const j=require('$HOME/.claude/plugins/installed_plugins.json').plugins||{};
process.exit(Object.keys(j).some(k=>k.split('@')[0]==='diagram-design')?0:1)
" && echo "diagram-design 已安装（via installed_plugins.json）"

# 方法 3：使用 claude CLI（较慢）
claude plugin list 2>/dev/null | grep -q "diagram-design" && echo "diagram-design 已安装（via CLI）"
```

## 安装 diagram-design

```bash
# 使用 cc-baseline 安装脚本（推荐）
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/install-diagram-design.sh

# 或手动安装
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
```

## 使用示例

### 示例 1：架构图（→ diagram-design）

**用户需求**：
```
"画一个系统架构图：前端（Vue）、后端（Spring Boot）、数据库（MySQL）、缓存（Redis）"
```

**路由决策**：
- 关键词：`架构图` → diagram-design
- 检查已安装 → 直接使用
- 未安装 → 提示安装

**执行**：
```
"画一个系统架构图：前端（Vue）、后端（Spring Boot）、数据库（MySQL）、缓存（Redis）"
```

### 示例 2：KPI 看板（→ co-infographic-generator）

**用户需求**：
```
"把这些指标做成看板：用户数 10 万、日活 2 万、GMV 500 万、转化率 15%"
```

**路由决策**：
- 关键词：`看板`、`指标` → co-infographic-generator
- 这是信息展示，不是技术图表

**执行**：
使用本 skill 的 `kpi-dashboard.html` 模板

### 示例 3：用户注册流程（→ diagram-design）

**用户需求**：
```
"画一个用户注册流程图，包含邮箱验证和手机验证两个分支"
```

**路由决策**：
- 关键词：`流程图`、`分支` → diagram-design
- 有分支决策，不适合简单步骤流程

**执行**：
```
"画一个用户注册流程图，包含邮箱验证和手机验证两个分支"
```

### 示例 4：简单步骤（→ co-infographic-generator）

**用户需求**：
```
"把部署步骤做成图：1. 打包代码  2. 上传服务器  3. 重启服务  4. 验证上线"
```

**路由决策**：
- 关键词：`步骤` + 无分支 → co-infographic-generator
- 纯线性步骤，适合信息图展示

**执行**：
使用本 skill 的 `step-flow.html` 模板

### 示例 5：四象限（→ diagram-design）

**用户需求**：
```
"画一个四象限图，横轴是影响力，纵轴是难度，展示 Q2 项目优先级"
```

**路由决策**：
- 关键词：`四象限` → diagram-design
- 标准业务分析图表

**执行**：
```
"画一个四象限图，横轴是影响力，纵轴是难度，展示 Q2 项目"
```

## 提示用户安装的模板话术

```
检测到您需要画 [架构图/流程图/时序图/...]，推荐使用 diagram-design 插件：

✨ 特点：
  - 27 种专业图表类型
  - 自动匹配品牌配色（60 秒配置）
  - 输出独立 HTML，支持导出 PNG/SVG
  - 4px 网格对齐，专业排版

是否现在安装？

安装命令：
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/install-diagram-design.sh

（安装约需 10-30 秒，安装后重启会话或 /reload-plugins）
```

## 降级处理

如果用户拒绝安装 diagram-design，或紧急需求无法等待安装，可以：

1. **技术流程图** → 使用 Mermaid 代码块（简单但不够美观）
2. **简单架构图** → 使用本 skill 的自定义组合（手动拼卡片+箭头）
3. **提醒局限**：
   ```
   "注意：使用 co-infographic-generator 降级方案，可能无法达到 diagram-design 的专业水准。
   建议后续安装 diagram-design 以获得更好效果。"
   ```

## 配合全局规范

根据全局 CLAUDE.md 的「文档配图统一用 co-infographic-generator」规范，补充如下：

> 任何文档（博客文章、README、设计文档、汇报材料等）需要生成高级 / 高大上的配图、插图、图表时：
> 1. **优先判断是否属于 diagram-design 的 27 种标准图表类型**（架构/流程/时序/状态/ER/泳道/四象限/时间线/甘特/循环/金字塔/韦恩等）
>    - 是 → 使用 diagram-design
>    - 否 → 继续判断
> 2. **判断是否为信息图**（KPI 看板/要点卡片/对比图/简单步骤）
>    - 是 → 使用 co-infographic-generator
>    - 否 → 继续判断
> 3. **判断是否为纯数据统计图**（柱/折/饼/散点）
>    - 是 → 使用 multi-chart-draw 的 ECharts
>    - 否 → 优先尝试 diagram-design（覆盖面最广）

## 总结

**记住三个原则**：
1. **标准化技术图表** → diagram-design（27 种类型，品牌一致）
2. **自由排版信息图** → co-infographic-generator（像素级控制，视觉效果）
3. **纯数据统计图** → multi-chart-draw（交互式，大数据量）

**优先级**：diagram-design > co-infographic-generator > multi-chart-draw > Mermaid/手动

**安装检查**：每次画图前先检查 diagram-design 是否已安装，未安装时提示用户
