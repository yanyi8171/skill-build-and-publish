# skill-build-and-publish

把“创建、测试、登记、GitHub 包装、确认发布和跨客户端回装验证”串成一条个人 Skill 生产流水线。用户提到“创建一个可公开发布的 Skill”“检查 Skill 能不能发布”“包装 Skill 但先别上传”“把 Skill 发布到 GitHub”“生成 README、许可证、安装命令或 Release ZIP”时都应使用本 Skill。它只从本地技能真源库复制发布副本，绝不让 GitHub 版本反向覆盖真源；任何公开仓库、推送、Tag 或 Release 操作前必须展示预览并取得明确确认。Orchestrate creation, evaluation, local registration, safe GitHub staging, explicit publish confirmation, and client installation verification for Agent Skills.

## 使用范围／Scope

> 这是作者为自己的 Windows 工作台编写的个人工具，默认依赖当前技能真源库结构、PowerShell，以及同级的 skill-creator 和 release-skills。公开仓库主要用于个人备份、跨设备保存和分享实现思路；其他设备、操作系统、目录结构或 Agent 客户端未必兼容，请先审阅脚本并按自己的环境调整，不承诺开箱即用。
>
> This is a personal tool built for the author's Windows workspace. It assumes the current true-source skill layout, PowerShell, and sibling skill-creator and release-skills. The public repository is mainly for personal backup and sharing the workflow. Other devices, operating systems, directory layouts, or Agent clients may not be compatible; review and adapt it before use. No out-of-the-box compatibility is promised.

## 支持范围／Compatibility

本仓库使用通用 Agent Skills 目录结构。真正负责发现、安装和运行 Skill 的是 Agent 客户端，而不是模型本身。

This repository follows the common Agent Skills directory layout. Skill discovery and execution depend on the Agent client, not the underlying model alone.

| 客户端 | 安装方式 | 状态 |
|---|---|---|
| Claude Code | GitHub CLI | 结构已验证，发布后需回装确认 |
| Codex | GitHub CLI／Skill Installer | 结构已验证，发布后需回装确认 |
| Hermes Agent | Skills Hub | 结构已验证，发布后需回装确认 |
| Tencent WorkBuddy | Release ZIP | ZIP 结构已验证，发布后需真机确认 |

## 安装／Install

### Claude Code

```powershell
gh skill install yy1675430-stack/skill-build-and-publish skill-build-and-publish --agent claude-code --scope user
```

### Codex

```powershell
gh skill install yy1675430-stack/skill-build-and-publish skill-build-and-publish --agent codex --scope user
```

也可以把下面的仓库地址交给 Codex 的 Skill Installer：

```text
https://github.com/yy1675430-stack/skill-build-and-publish/tree/main/skills/skill-build-and-publish
```

### Hermes Agent

```powershell
hermes skills install skills-sh/yy1675430-stack/skill-build-and-publish/skill-build-and-publish
```

### Tencent WorkBuddy

从 [GitHub Release](https://github.com/yy1675430-stack/skill-build-and-publish/releases/tag/v0.1.0) 下载 `skill-build-and-publish-v0.1.0.zip`，然后打开“专家技能连接器”→“技能”→“添加技能”→“上传技能”。等待安全检查完成后，在“已安装”中确认名称。

### 其他兼容客户端

```powershell
npx skills add yy1675430-stack/skill-build-and-publish --skill skill-build-and-publish -g
```

## 使用／Usage

安装后直接对 Agent 说：

```text
使用 skill-build-and-publish，帮我完成这个任务。先预检，再执行。
```

详细行为、输入要求和失败处理见 [`SKILL.md`](skills/skill-build-and-publish/SKILL.md)。

## 成功标志／Success

- Agent 的 Skill 列表中出现 `skill-build-and-publish`。
- Skill 能被真实任务触发，并按 `SKILL.md` 给出可检查结果。
- 重新运行时不覆盖原始资料，也不重复产生已有结果。

## 排查／Troubleshooting

1. 找不到 Skill：确认安装到了正确客户端和用户级目录，重启客户端后再查。
2. Skill 不触发：明确说“使用 skill-build-and-publish”，同时提供必要输入。
3. WorkBuddy 导入失败：确认上传的是 Release ZIP，且 ZIP 顶层的 `skill-build-and-publish` 文件夹内存在 `SKILL.md`。
4. 脚本无法运行：检查系统、外部工具和权限是否符合 `compatibility`。



## 许可证／License

[MIT](LICENSE)。允许使用、修改和再分发，但必须保留许可证和版权声明。

MIT licensed. Use, modification, and redistribution are allowed with the license and copyright notice retained.
