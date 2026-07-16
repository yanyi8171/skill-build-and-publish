# 个人 Skill 创建与发布标准

## 两层结构

### Skill 真源层

只放执行能力真正需要的文件：

- `SKILL.md`：必需。
- `scripts/`：确定性、重复性工作才需要。
- `references/`：只在任务中按需读取的详细说明。
- `assets/`：输出模板、图标、字体等实际资源。
- `evals/evals.json`：至少三个真实测试。
- 依赖锁文件：只有存在外部运行依赖时才需要。

不要为了“看起来完整”创建空目录。真源只在当前工作台的技能真源库维护。

### GitHub 发布层

由包装脚本重新生成：

- 双语 `README.md`。
- `LICENSE`。
- `CHANGELOG.md` 与 `VERSION`。
- `.gitignore`、`.gitattributes`。
- `.github/workflows/validate.yml`。
- `skills/<skill-name>/` 真源副本。
- Release ZIP，不提交进 Git 仓库，只作为 Release 附件上传。

只有确实引用、下载或捆绑第三方项目时才增加 `THIRD_PARTY_NOTICES.md`。徽章、网站、贡献指南和宣传截图不是首发必需品。

## 发布前硬门槛

- 目录名与 frontmatter `name` 完全一致。
- `description` 同时覆盖能力、触发语和不应触发的近邻场景。
- `license`、`compatibility`、`metadata.author`、`metadata.version` 完整。
- 版本符合 `主版本.次版本.修订号`。
- 所有本地引用存在。
- 至少三个真实测试完成。
- 不含 `TODO_PUBLICATION`、依赖缓存、`.env`、Cookie、私钥、令牌或个人用户目录。
- 脚本型 Skill 具有失败处理、重复运行保护和原始资料保护。
- 包装前后真源目录哈希一致。

## 版本默认值

- 首次可用版本：`0.1.0`。
- 修复错误且不改变用法：修订号加一，例如 `0.1.0 → 0.1.1`。
- 增加兼容能力或新功能：次版本加一，例如 `0.1.1 → 0.2.0`。
- 改变输入、输出或删除原有能力：主版本加一，并写迁移说明。

版本、Tag 和 Release 使用同一数字；Tag 加 `v` 前缀。

## 隐私与安全

- 扫描所有可读文本，但报告只显示文件名和命中类型，不回显密钥内容。
- GitHub 只接收临时副本；不把 `.git` 放进真源。
- 不自动读取浏览器 Cookie、系统凭据或 GitHub Token。
- 公开仓库默认为 MIT，但发布前仍向用户展示可见性和许可证。
- 外部发布必须是当前对话中的明确授权，旧授权不能自动沿用到新版本。

## README 最小内容

1. 一句话说明能做什么。
2. 客户端支持状态，区分“已验证”和“结构兼容”。
3. Claude Code、Codex、Hermes、WorkBuddy 和通用安装方式。
4. 一个真实使用示例。
5. 成功标志。
6. 排查步骤。
7. 安全边界和许可证。

不要写不存在的命令，也不要把模型名称等同于客户端支持。
