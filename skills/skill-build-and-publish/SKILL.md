---
name: skill-build-and-publish
description: 把“创建、测试、登记、GitHub 包装、确认发布和跨客户端回装验证”串成一条个人 Skill 生产流水线。用户提到“创建一个可公开发布的 Skill”“检查 Skill 能不能发布”“包装 Skill 但先别上传”“把 Skill 发布到 GitHub”“生成 README、许可证、安装命令或 Release ZIP”时都应使用本 Skill。它只从本地技能真源库复制发布副本，绝不让 GitHub 版本反向覆盖真源；任何公开仓库、推送、Tag 或 Release 操作前必须展示预览并取得明确确认。Orchestrate creation, evaluation, local registration, safe GitHub staging, explicit publish confirmation, and client installation verification for Agent Skills.
license: MIT
compatibility: 个人版，面向 Windows 10/11、PowerShell 5.1+、当前技能真源库结构；创建与包装不需要 GitHub 登录，真正发布需要 git、GitHub CLI 和已授权账号。产出的 Skill 采用通用 Agent Skills 结构，目标客户端包括 Claude Code、Codex、Hermes 和 WorkBuddy。
metadata:
  author: yy1675430-stack
  version: "0.1.2"
---

# Skill 创建与发布总控

把 Skill 本体当作唯一真源，把 GitHub 仓库、README 和 Release ZIP 当作可重新生成的发布副本。先证明 Skill 好用，再登记和包装；公开发布永远是最后一道人工闸门。

## 固定边界

- 唯一可编辑实体位于技能真源库；桥接目录和 GitHub 暂存目录都不是来源。
- 不从 GitHub 下载内容覆盖真源，也不让包装脚本写回源 Skill。
- 不删除或覆盖已有 Skill。新建脚本发现同名目录时必须停止。
- 不把密钥、Cookie、浏览器资料、个人用户目录、`.env`、私钥或依赖缓存放进发布包。
- 创建、检查、包装可以直接执行；创建仓库、推送、Tag、Release 必须先让用户确认。
- “支持某模型”要改写成“支持某 Agent 客户端”。模型本身不负责安装 Skill。

## 先判断用户处于哪种模式

| 用户意图 | 模式 | 可以直接做什么 |
|---|---|---|
| “创建一个可公开发布的 Skill” | 创建 | 定义需求、建真源骨架、编写、测试、登记 |
| “检查 XXX 是否可以发布” | 预检 | 只读扫描并给出错误、警告和文件清单 |
| “包装 XXX，先不要上传” | 包装 | 生成临时仓库、README、许可证、工作流和 ZIP |
| “发布 XXX 到 GitHub” | 发布 | 先预检和包装，展示预览后停下等待确认 |

如果用户只要求其中一个模式，不要顺手扩大到下一阶段。

## 阶段一：定义与创建

1. 从对话中先提取：目标、触发语、输入、输出、成功标准、依赖、隐私边界、目标客户端。
2. 只有会显著改变 Skill 行为的信息缺失时才询问；普通细节采用保守默认值。
3. 完整阅读同级 `skill-creator/SKILL.md`，用它完成内容设计、真实测试和迭代。不要复制其中的长篇方法到本 Skill。
4. 需要新骨架时运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill>\scripts\new-skill.ps1" `
  -Name "<skill-name>" `
  -DescriptionZh "<中文触发说明>" `
  -DescriptionEn "<English trigger description>" `
  -TestPrompt "<正常任务>","<缺输入任务>","<边界任务>"
```

5. 脚本只创建 `SKILL.md` 和 `evals/evals.json`，不会覆盖同名目录，也不会自动登记未完成草稿。
6. 删除 `TODO_PUBLICATION` 标记前，补齐真实工作流、失败处理、引用资源和验收标准。

## 阶段二：测试与迭代

至少覆盖三类真实任务：正常任务、缺少关键信息、相似但不应触发的边界任务。具有确定输出的脚本型 Skill 还应加入自动测试；写作或审美型 Skill 以人工比较为主。

测试完成后检查：

- Skill 是否比不使用时更稳定、少走弯路。
- `description` 是否同时说明“做什么”和“什么时候触发”。
- 失败时是否停止在安全位置，而不是继续猜测、覆盖或绕过权限。
- 重复运行是否保留原始资料并避免重复结果。

## 阶段三：发布预检

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill>\scripts\preflight.ps1" -SkillName "<skill-name>"
```

预检只读，检查 frontmatter、版本、引用文件、测试案例、依赖缓存、敏感文件、常见密钥和个人用户路径。出现任何 `ERROR` 都不得进入包装；`WARN` 必须向用户解释，但不一定阻塞。

详细规则见 `references/publishing-standard.md`。

## 阶段四：登记真源

只有真实测试和预检通过后才更新 `skills-lock.json`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill>\scripts\update-skill-lock.ps1" -SkillName "<skill-name>"
```

脚本按工作台现行规则计算规范化 SHA-256，并在临时目录保存锁文件备份。写入失败会恢复原内容；不得通过替换文件破坏现有硬链接。

## 阶段五：只包装，不发布

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill>\scripts\package-skill.ps1" -SkillName "<skill-name>"
```

包装脚本会：

1. 再次预检。
2. 计算真源目录哈希。
3. 只读复制到系统临时目录。
4. 生成双语 README、MIT LICENSE、CHANGELOG、VERSION、`.gitignore`、`.gitattributes` 和 GitHub Actions。
5. 生成顶层包含 Skill 文件夹的 Release ZIP。
6. 再算一次真源哈希，确认源文件完全未变。
7. 生成 `publish-manifest.json`，但不执行 `git` 或 `gh`。

个人工具、特定系统或尚未完成跨设备验证的 Skill，包装时使用 `-RepositoryNotice "<适用范围说明>"`，把限制直接放在 README 首屏；不要用模糊的“可能不兼容”代替具体依赖和已验证环境。

向用户报告：预检结果、版本、公开／私有、文件清单、暂存仓库路径、ZIP 路径、源未改变证明，以及发布所需的精确确认口令。

## 阶段六：公开发布闸门

用户没有确认时必须停下。不要把“帮我包装”“以后准备发布”“看看能不能传”理解成发布授权。

首次创建新仓库时，用户确认后才运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill>\scripts\publish-skill.ps1" `
  -ManifestPath "<publish-manifest.json>" `
  -ConfirmPublish `
  -ConfirmationText "PUBLISH <owner>/<skill-name> v<version> PUBLIC"
```

脚本要求确认口令逐字匹配，并拒绝覆盖已存在的远程仓库。发布已有仓库的新版本时，不使用该首次发布脚本；完整阅读同级 `release-skills/SKILL.md`，克隆现有仓库、核对差异、确定版本、再次确认后再发布。

## 阶段七：回装验证

发布成功不等于交付完成。按 `references/verification-matrix.md` 依次验证：

1. GitHub CLI 能发现且安装唯一 Skill。
2. Claude Code 和 Codex 用户级安装成功。
3. Hermes 能 inspect／install。
4. Release ZIP 顶层结构正确；WorkBuddy 真机验证需要用户配合界面操作。
5. 至少在一个真实客户端运行一次真实任务。

只有实际验证过的安装方式才能在 README 中标为“已验证”；其他方式标为“结构兼容，待验证”。

## 最终报告

每次结束都用同一顺序报告：

1. 当前停在哪个阶段。
2. 修改或生成了什么。
3. 真源、暂存仓库、ZIP、GitHub 和 Release 的位置。
4. 测试和预检结果。
5. 是否发生外部发布。
6. 下一步需要用户确认什么。

## 排查

- 找不到真源：确认本 Skill 是从工作台的真源库桥接使用，不要改桥接目录中的副本。
- 预检误报：先定位具体文件和命中类型；不要为了通过检查整体关闭隐私扫描。
- 包装失败：检查临时目录权限和 ZIP 是否被其他程序占用；重新生成新的暂存目录，不覆盖旧暂存。
- 发布拒绝：核对确认口令、GitHub CLI 授权和仓库是否已经存在。
- 已有仓库更新：转入 `release-skills`，不要用首次发布脚本重建或强推仓库。
