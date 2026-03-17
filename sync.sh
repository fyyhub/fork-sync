#!/usr/bin/env bash
set -euo pipefail

# ─── 参数解析 ───
FORCE=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --force)  FORCE=true ;;
    --dry-run) DRY_RUN=true ;;
  esac
done

# ─── 颜色（CI 环境下也能用） ───
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ─── 排除列表 ───
IFS=',' read -ra EXCLUDES <<< "${EXCLUDE_REPOS:-}"

is_excluded() {
  local repo="$1"
  for ex in "${EXCLUDES[@]}"; do
    ex="$(echo "$ex" | xargs)" # trim
    [[ -n "$ex" && "$repo" == "$ex" ]] && return 0
  done
  return 1
}

# ─── 获取所有 fork ───
echo "🔍 正在获取所有 fork 仓库..."
FORKS_JSON=$(gh repo list --fork --limit 1000 
  --json nameWithOwner,parent,isArchived 
  --jq '[.[] | select(.isArchived == false)]')

TOTAL=$(echo "$FORKS_JSON" | jq 'length')
echo "📦 发现 ${TOTAL} 个活跃的 fork 仓库"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  echo "没有需要同步的 fork，退出。"
  exit 0
fi

# ─── 计数器 ───
SUCCESS=0
SKIPPED=0
FAILED=0
UPTODATE=0
declare -a FAIL_LIST=()
declare -a SKIP_LIST=()
declare -a OK_LIST=()

# ─── 遍历同步 ───
for i in $(seq 0 $((TOTAL - 1))); do
  REPO=$(echo "$FORKS_JSON" | jq -r ".[$i].nameWithOwner")
  PARENT=$(echo "$FORKS_JSON" | jq -r ".[$i].parent.nameWithOwner // empty")

  echo "────────────────────────────────────────"
  echo "[$((i + 1))/${TOTAL}] ${REPO}"

  # 检查排除列表
  if is_excluded "$REPO"; then
    echo -e "  ${YELLOW}⏭ 跳过（在排除列表中）${NC}"
    SKIPPED=$((SKIPPED + 1))
    SKIP_LIST+=("${REPO} — 在排除列表中")
    continue
  fi

  # 检查上游是否存在
  if [[ -z "$PARENT" ]]; then
    echo -e "  ${YELLOW}⏭ 跳过（上游仓库不存在或已删除）${NC}"
    SKIPPED=$((SKIPPED + 1))
    SKIP_LIST+=("${REPO} — 上游不存在")
    continue
  fi

  echo "  ↑ upstream: ${PARENT}"

  # Dry run 模式
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}🔍 [dry-run] 将会同步此仓库${NC}"
    continue
  fi

  # 执行同步
  SYNC_ARGS=("$REPO")
  if [[ "$FORCE" == "true" ]]; then
    SYNC_ARGS+=("--force")
  fi

  OUTPUT=""
  if OUTPUT=$(gh repo sync "${SYNC_ARGS[@]}" 2>&1); then
    if echo "$OUTPUT" | grep -qi "already up to date\|no new commits"; then
      echo -e "  ${GREEN}✓ 已是最新${NC}"
      UPTODATE=$((UPTODATE + 1))
    else
      echo -e "  ${GREEN}✓ 同步成功${NC}"
      SUCCESS=$((SUCCESS + 1))
      OK_LIST+=("$REPO")
    fi
  else
    # 同步失败 — 可能是冲突
    if echo "$OUTPUT" | grep -qi "conflict\|diverged"; then
      if [[ "$FORCE" == "true" ]]; then
        echo -e "  ${RED}✗ 强制同步也失败了${NC}"
      else
        echo -e "  ${YELLOW}⚠ 有冲突，跳过（使用 --force 可覆盖）${NC}"
      fi
    elif echo "$OUTPUT" | grep -qi "rate limit"; then
      echo -e "  ${RED}✗ 触发 API 限流，终止同步${NC}"
      FAILED=$((FAILED + 1))
      FAIL_LIST+=("${REPO} — API rate limit")
      break
    elif echo "$OUTPUT" | grep -qi "401\|403\|authentication\|token"; then
      echo -e "  ${RED}✗ 认证失败，请检查 SYNC_PAT 权限或是否过期${NC}"
      FAILED=$((FAILED + 1))
      FAIL_LIST+=("${REPO} — 认证失败")
      break
    else
      echo -e "  ${RED}✗ 同步失败: ${OUTPUT}${NC}"
    fi
    FAILED=$((FAILED + 1))
    FAIL_LIST+=("${REPO} — ${OUTPUT}")
  fi

  # 避免触发限流
  sleep 1
done

# ─── 汇总报告 ───
echo ""
echo "════════════════════════════════════════"
echo "📊 同步报告"
echo "════════════════════════════════════════"
echo "  总计:     ${TOTAL}"
echo "  已更新:   ${SUCCESS}"
echo "  已是最新: ${UPTODATE}"
echo "  跳过:     ${SKIPPED}"
echo "  失败:     ${FAILED}"

if [[ ${#FAIL_LIST[@]} -gt 0 ]]; then
  echo ""
  echo "❌ 失败详情:"
  for item in "${FAIL_LIST[@]}"; do
    echo "  - ${item}"
  done
fi

if [[ ${#SKIP_LIST[@]} -gt 0 ]]; then
  echo ""
  echo "⏭ 跳过详情:"
  for item in "${SKIP_LIST[@]}"; do
    echo "  - ${item}"
  done
fi

# ─── GitHub Actions Step Summary ───
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## 🔄 Fork 同步报告"
    echo ""
    echo "| 指标 | 数量 |"
    echo "|------|------|"
    echo "| 总计 | ${TOTAL} |"
    echo "| ✅ 已更新 | ${SUCCESS} |"
    echo "| ✅ 已是最新 | ${UPTODATE} |"
    echo "| ⏭ 跳过 | ${SKIPPED} |"
    echo "| ❌ 失败 | ${FAILED} |"

    if [[ ${#OK_LIST[@]} -gt 0 ]]; then
      echo ""
      echo "### ✅ 已更新的仓库"
      for item in "${OK_LIST[@]}"; do
        echo "- `${item}`"
      done
    fi

    if [[ ${#FAIL_LIST[@]} -gt 0 ]]; then
      echo ""
      echo "### ❌ 失败的仓库"
      for item in "${FAIL_LIST[@]}"; do
        echo "- ${item}"
      done
    fi

    if [[ ${#SKIP_LIST[@]} -gt 0 ]]; then
      echo ""
      echo "### ⏭ 跳过的仓库"
      for item in "${SKIP_LIST[@]}"; do
        echo "- ${item}"
      done
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

# 如果有失败则退出码非零（可选，取消注释启用）
# [[ "$FAILED" -gt 0 ]] && exit 1
exit 0
