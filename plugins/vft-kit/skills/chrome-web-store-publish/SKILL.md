---
name: chrome-web-store-publish
description: 使用 ego-browser 预检、创建、填写、复核并发布 Chrome Web Store 扩展，支持读取用户提供的发布资料 JSON 模板自动填写商品详情、隐私、分发和测试说明。用户要求上传 Chrome 插件、新建商店商品、填写权限理由或数据使用、保存草稿、提交审核、发布上架、复用历史插件发布信息时使用。
---

# Chrome Web Store Publish

使用 `ego-browser` 操作 Chrome Web Store Developer Dashboard；执行浏览器动作前完整读取 `ego-browser` skill，并在整个任务中复用同一 task space。

## 输入与模板

先定位根目录含 `manifest.json` 的发布 ZIP 或解压目录。用户提供资料模板时读取该文件；未提供时复制并填写 [publish-profile.template.json](assets/publish-profile.template.json)。模板只能提供默认值，按以下优先级合并：

1. 实际发布包、manifest 和源码证据。
2. 用户当前消息中的明确要求。
3. 用户提供的模板。
4. 仪表板现有草稿值。

高优先级与模板冲突时停止并报告，不得用模板覆盖实际权限、远程代码或数据使用事实。模板不是“提交审核”或“发布”的授权。

运行预检：

```bash
node <skill-dir>/scripts/preflight.mjs <extension-directory-or-zip> [--profile /path/to/publish-profile.json]
```

预检失败时停止。还要运行仓库已有的构建、测试、类型检查和压缩包完整性校验。

## 授权边界

- “检查/准备”只读。
- “创建/填写/上传”允许创建商品、上传包并保存草稿，不允许提交审核。
- “提交审核”只授权当前已核对的发布者、商品、版本和可见性。
- “发布/上架”必须由用户最新消息明确授权。最终点击前报告发布者、商品、版本、价格、可见性、地区和审核后发布方式。
- 默认审核通过后手动发布；除非用户明确要求自动发布。
- 交易者身份、公开邮箱和邮寄地址默认保持现状。缺失或平台强制更新时交还浏览器让用户填写，不在模板或日志中保存这些值。
- 登录、验证码、付款、协议和法律声明均交还用户处理。

## 预检事实

检查每项权限的真实调用方，并搜索远程脚本/Wasm、`eval`/`new Function`、分析上报、网络上传、storage、cookies、history、页面内容、认证信息、截图和请求体处理。不能证明的声明不得编造。

多变体时遵循仓库发布文档；否则对比权限后让用户选择，避免上传开发版或高权限版。

## 填写草稿

1. 打开模板指定或用户给出的发布者仪表板，确认账号与发布者。
2. 上传已验证 ZIP，核对平台解析出的名称、版本、语言、权限和包类型。
3. 按 locale 填写描述、分类、128x128 图标、截图、官网、主页和支持链接。截图只能使用 1280x800 或 640x400 的 JPEG/无 alpha 24-bit PNG。
4. 填写隐私页：
   - 写一个与真实功能一致的单一用途说明。
   - 为每项 permission 和 host pattern 写实现依据。
   - 准确声明远程代码。
   - 进入“数据使用”后先把全部用户数据类别取消勾选，禁止继承其他商品或浏览器残留状态。
   - 仅勾选源码或用户事实能证明的类别；没有证据时全部保持未勾选。证据表明会处理数据但用户要求不勾选时，只保存草稿并报告冲突。
   - 三项有限用途确认与数据类别分开处理，只在声明真实时勾选。
   - 隐私政策 URL 只在用户提供或平台按真实数据声明强制要求时填写；不得虚构链接。
5. 填写价格、可见性、地区和审核后发布方式。
6. 仅在确有登录、特殊页面、DevTools、side panel、debugger 或非直观步骤时填写测试说明；不得放可复用个人凭据。
7. 保存草稿，再逐页重开核对所有文本、媒体和复选框是否持久化。

## 提交与完成

提交或发布前输出：

```text
Publisher: <name/id>
Item: <name/id>
Version: <version>
Visibility: <public/unlisted/private>
Payment: <free/IAP>
Regions: <selection>
Review: <submit/not submit>
After approval: <manual/automatic publication>
```

只执行已授权动作。完成后回读状态，并报告使用的包、发布者/商品 ID、版本、保存/提交/发布状态、截图数、权限和剩余阻塞；停止在草稿时必须明确说明。

浏览器定位优先 `snapshotText()` 和稳定的 `loc=`/CSS；导航、上传、保存或切换 locale 后重新观察，不复用旧 `@ref`。用户接管后立即停止，收到明确消息再用 `takeOverTaskSpace()` 恢复。
