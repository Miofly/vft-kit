---
description: 切换 caveman 风格档位（无参数=caveman，ultra，wenyan，status）；关闭说 stop caveman
argument-hint: "[ultra|wenyan|status]"
disable-model-invocation: true
managed-by: vft-kit vendor-plugin-hooks
---
`/caveman $ARGUMENTS` was handled by the caveman UserPromptSubmit hook, which already switched the mode and injected the matching ruleset. Follow that ruleset. Reply in one line: `Caveman mode: <mode>`, using the hook's mode value.
