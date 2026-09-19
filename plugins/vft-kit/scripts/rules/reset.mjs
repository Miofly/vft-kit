#!/usr/bin/env node
/**
 * SessionStart（matcher: compact|clear）：上下文被压缩或清空后，之前注入的规则正文已不在上下文里，
 * 清掉会话注入记录，让下一次命中重新注入。
 */
import { readHookInput, resetInjected } from './lib.mjs';

readHookInput()
  .then(input => resetInjected(input?.session_id))
  .catch(() => {})
  .finally(() => process.exit(0));
