# 发布后的安装验证

把 `<owner>`、`<repo>`、`<skill>` 和 `<version>` 替换成实际值。每次测试尽量安装到临时或用户级目录，不覆盖真源库。

## 仓库结构

```powershell
gh api "repos/<owner>/<repo>/git/trees/v<version>?recursive=1"
```

成功标志：存在且只存在目标 `skills/<skill>/SKILL.md`，没有 `.env`、Cookie、私钥和依赖缓存。

## Claude Code

```powershell
gh skill install <owner>/<repo> <skill> --agent claude-code --scope user
```

成功标志：命令成功，Claude Code 重启后能看到 `<skill>`。

## Codex

```powershell
gh skill install <owner>/<repo> <skill> --agent codex --scope user
```

也可把下面地址交给 Codex Skill Installer：

```text
https://github.com/<owner>/<repo>/tree/main/skills/<skill>
```

成功标志：Codex 的可用 Skill 列表出现 `<skill>`，并能用一个真实任务触发。

## Hermes

先检查标准化标识，再安装：

```powershell
hermes skills inspect skills-sh/<owner>/<repo>/<skill>
hermes skills install skills-sh/<owner>/<repo>/<skill>
hermes skills audit
```

成功标志：inspect 能识别 Skill，install 成功，audit 不报告高风险问题。

## WorkBuddy

1. 下载 Release 附件 `<skill>-v<version>.zip`。
2. 打开“专家技能连接器”→“技能”→“添加技能”→“上传技能”。
3. 选择 ZIP，等待安全扫描，不跳过检查。
4. 在“已安装”中核对名称和描述。

成功标志：ZIP 被识别，安全扫描通过，已安装列表出现 `<skill>`。

## 通用客户端

```powershell
npx skills add <owner>/<repo> --skill <skill> -g
```

成功标志：工具只发现目标 Skill，并报告全局安装成功。

## 常见排查

1. 找不到 Skill：检查仓库布局、目标客户端名和安装作用域。
2. 安装成功但不显示：重启客户端，再查用户级 Skill 目录。
3. WorkBuddy 拒绝 ZIP：打开 ZIP，确认顶层 `<skill>` 文件夹内直接包含 `SKILL.md`。
4. Hermes 标识失败：先运行 inspect，使用它返回的标准化 `skills-sh/...` 标识。
5. 多 Skill 被误发现：检查仓库是否残留测试 Skill 或旧目录。
