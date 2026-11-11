# Ghidra 脚本（wechat.dylib RVA 派生用）

用法（持久 project，分析一次后 `-process` 复用）：

```bash
GH="$GHIDRA_INSTALL_DIR/support/analyzeHeadless"
# 首次：导入，--noanalysis 足够（Mach-O loader 在导入阶段就解掉了 chained fixup）
GHIDRA_MAXMEM=6G "$GH" /tmp/ghproj wechat -import /tmp/wechat_arm64.dylib -noanalysis \
  -scriptPath "$(dirname "$0")" -postScript ScanQtRefs.java
# 之后复用
GHIDRA_MAXMEM=6G "$GH" /tmp/ghproj wechat -process -noanalysis \
  -scriptPath "$(dirname "$0")" -postScript ScanQtMeta.java
```

| 脚本 | 作用 |
|---|---|
| `ScanQtRefs.java` | 打印所有内存块、Qt moc 字符串地址、以及每条指向该字符串区的数据引用 |
| `ScanQtMeta.java` | 按「3 个连续指针指向 __TEXT/__text」的签名找 `QMetaObject` 结构 |
| `Probe.java` | 打印当前 project 的函数数/符号数/语言（判断残留状态） |

**实测边界（本机 WeChat 4.1.10，2026-11-10）**：

- `-noanalysis` 导入即可用：Ghidra **在导入阶段就解析了 LC_DYLD_CHAINED_FIXUPS**，内存里是明文指针。所以「扫指针找引用」在 Ghidra 里成立，在裸文件字节上不成立。
- `ScanQtRefs` 输出与自写 `macho_chained_fixups.py` 交叉一致：指向 `[0x87b0000,0x8a83000]` 的引用 **62,569（Ghidra）vs 62,564（自写）**。
- `ScanQtMeta` 的签名**不可靠**：命中的是 C++ RTTI `type_info` 结构（名字形如 `N10mars_boost12bad_any_castE`），不是 Qt 元对象。Qt 的 `QMetaObject` 在这份 build 里**没有**被该签名命中 → 紧凑/相对偏移布局，需要 Qt6 元对象感知的解析。
- 符号表 443,793 条里**没有任何 Qt 符号**（无 `_ZN7Q*`），Qt 内部函数全是匿名 `FUN_*`。
- `-noanalysis` 只建出 **3436 个函数**（`__stubs` 里的绑定导入），不是 342,114 个真实函数边界；要拿到函数体需要完整自动分析 → 本机 24 GB / swap 打满时会卡死（实测 RSS 涨到 1.37 GB 后 CPU 掉到 10%、日志停更）。
