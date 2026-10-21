# notify-qr.py 推送与 env 供给桥

## notify-qr.py 的 env 供给桥

脚本本身不读任何密钥文件；调用方负责 export：

| 环境变量 | 含义 | 默认 |
|---|---|---|
| `PUSHPLUS_TOKEN` | PushPlus 消息 token（必需） | 无 |
| `PUSHPLUS_TOPIC` | 群组编码 | `me` |
| `PUSHPLUS_SEND_URL` | 发送接口 | `https://www.pushplus.plus/send` |
| `BEEIMG_TOKEN` / `BEEIMG_UPLOAD_URL` / `BEEIMG_STORAGE_ID` | 主图床 | 无 token 时回退 Uguu |
| `UGUU_UPLOAD_URL` | 匿名兜底图床 | `https://uguu.se/upload` |
| `NTFY_BASE_URL` / `NTFY_TOPIC` / `NTFY_TOKEN` / `NTFY_ALLOW_SHORT_TOPIC` | 附加提醒，可全缺 | 缺则 skipped |

`--title-prefix 公众号` 可复用公众号流程的标题格式。调用方负责从自己的凭据存储导出这些 env；公共脚本不读取仓库内的凭据文件。

ntfy 的通用发送、macOS 接收端、自启和订阅看门狗由 `vft-kit:notify` 维护；本 skill 只保留“PushPlus 成功后发送二维码附件、ntfy 失败不阻塞”的扫码业务语义。
