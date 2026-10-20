
## Bash 命令避开内置确认框

- rm/git 的内置确认框 bypass 和 hook 都放行不了，写命令时主动避开：删除只写字面绝对路径（按会话当前目录判断，不 cd 进要删的目录），变量用 `"${VAR:?}"`；git 一律 `git -C <绝对路径>`。hook `bash-prompt-guard.py` 会拦下并给改写提示，照改重发。
