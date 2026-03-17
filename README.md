# 🔄 Fork Sync

自动同步你 GitHub 上所有 fork 仓库与上游保持一致。

一个仓库，一个 Action，管理所有 fork。

## 工作原理

- 使用 `gh repo list --fork` 自动发现你的所有 fork
- 使用 `gh repo sync` 通过 GitHub API **服务端同步**（无需 clone 仓库到 runner）
- 自动跳过已归档的仓库和上游已删除的 fork
- 冲突时安全跳过，不会覆盖你的自定义提交

## 快速开始

### 1. 创建仓库

在 GitHub 上创建一个新仓库（如 `fork-sync`），将本项目的文件推上去。

### 2. 创建 Personal Access Token

前往 [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)

**推荐使用 Fine-grained token：**
- Token name: `fork-sync`
- Expiration: 按需设置（建议 90 天，到期前记得更新）
- Repository access: `All repositories`
- Permissions:
  - `Contents`: Read and Write

**或使用 Classic token：**
- 勾选 `repo` scope

### 3. 添加 Secret

进入 fork-sync 仓库 → Settings → Secrets and variables → Actions → New repository secret

- Name: `SYNC_PAT`
- Value: 粘贴上一步创建的 token

### 4. 完成 ✅

Action 会每天 UTC 6:00（北京时间 14:00）自动运行。

## 手动触发

进入 Actions 页面 → `Sync All Forks` → `Run workflow`

可选参数：
- **force**: 强制同步（会覆盖 fork 上与上游有冲突的提交）
- **dry_run**: 仅列出所有 fork，不执行同步操作

## 排除特定仓库

编辑 `.github/workflows/sync-forks.yml` 中的 `EXCLUDE_REPOS` 环境变量：

```yaml
env:
  EXCLUDE_REPOS: "your-name/repo1,your-name/repo2"
```

## 运行报告

每次运行后，在 Actions → 对应的运行记录 → Summary 页面可查看 Markdown 格式的同步报告。

## FAQ

**Q: PAT 过期了怎么办？**
A: 重新创建一个 token，更新仓库的 `SYNC_PAT` secret 即可。

**Q: fork 上有自己的提交，会被覆盖吗？**
A: 默认不会。遇到冲突会跳过该仓库。只有手动触发并勾选 `force` 时才会强制覆盖。

**Q: 支持多少个 fork？**
A: 最多 1000 个。GitHub API 限流 5000 次/小时，每个 fork 约消耗 2 次调用，足够使用。

**Q: 费用？**
A: 公共仓库完全免费。私有仓库消耗 Actions 分钟数（Free 账户 2000 分钟/月），整个同步通常 1-2 分钟。

## License

MIT
