#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:-release}"
KSU_DIR="${2:-KernelSU}"

# 正式版：GitHub 新仓库 SukiSU-Nova/SukiSU-Nova 的稳定 Release。
# 滚动版：CNB 仓库 sukisu-nova/Release 的 manager-ci 分支 manifest.json。
# 旧端点 cnb.cool/shirkneko/sukisu-release 已被冻结（errcode 10003），不可再用。
GITHUB_LATEST="https://api.github.com/repos/SukiSU-Nova/SukiSU-Nova/releases/latest"
CNB_MANIFEST="https://cnb.cool/sukisu-nova/Release/-/git/raw/manager-ci/manifest.json"
ACCEPT="Accept: application/vnd.github+json"

case "$CHANNEL" in
  最新*|latest*|HEAD*) ROLLING=true ;;
  *) ROLLING=false ;;
esac

RELEASE=""
if [ "$ROLLING" = false ]; then
  RELEASE=$(curl -fsSL --retry 3 --max-time 30 -H "$ACCEPT" "$GITHUB_LATEST") || {
    STATUS=$?
    [ "$STATUS" -eq 22 ] || exit "$STATUS"
    RELEASE=""
  }
  if [ -z "$RELEASE" ]; then
    echo "::notice::未获取到 GitHub 正式版，已回退到 manager-ci 测试版"
    ROLLING=true
  fi
fi

if [ "$ROLLING" = true ]; then
  RELEASE=$(curl -fsSL --retry 3 --max-time 60 "$CNB_MANIFEST")
fi

TAG=$(printf '%s' "$RELEASE" | jq -r '.tag_name // empty')
ASSETS=$(printf '%s' "$RELEASE" | jq -r '
  [ .assets[]?
    | select(.name | test("release\\.apk$"; "i"))
    | select(.name | test("(?i)debug|spoofed") | not) ]
  | sort_by(if (.name | test("(?i)universal")) then 0
            elif (.name | test("(?i)arm64-v8a")) then 1 else 2 end)
  | .[] | [.name, .browser_download_url] | @tsv
')
if [ -z "$ASSETS" ]; then
  echo "::error::SukiSU-Nova $TAG 中没有可用的管理器 APK"
  exit 1
fi
IFS=$'\t' read -r APK_NAME _ <<< "$(printf '%s\n' "$ASSETS" | head -n 1)"
APK_NAME="${APK_NAME%$'\r'}"
if [[ "$APK_NAME" =~ _([0-9]+)(-(arm64-v8a|armeabi-v7a|armv7|riscv64|x86_64|x86|universal))?-release\.apk$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  echo "::error::无法从 SukiSU-Nova APK 文件名解析版本: $APK_NAME"
  exit 1
fi

# SukiSU-Nova 版本号公式（main/kernel/Kbuild 与 builtin/kernel/Makefile 共用）：
#   KSU_VERSION = 30000 + main 提交数 + 996
COMMIT=""
if [ "$ROLLING" = false ]; then
  # 正式通道：Release 标签在 git.zako.shirkneko.top 源仓库中解析（GitHub 上
  # 同名 tag 指向改名提交，计数不可用，必须在 CI 克隆的源仓库里查）。
  COMMIT=$(git -C "$KSU_DIR" rev-parse --verify "${TAG}^{commit}" 2>/dev/null || true)
  if [ -n "$COMMIT" ]; then
    COUNT=$(git -C "$KSU_DIR" rev-list --count "$COMMIT")
    ACTUAL_VERSION=$((30000 + COUNT + 996))
    if [ "$VERSION" -ne "$ACTUAL_VERSION" ]; then
      echo "::warning::SukiSU-Nova $TAG 的 APK 版本 $VERSION 与标签提交版本 $ACTUAL_VERSION 不一致，内核侧不锁定提交"
      COMMIT=""
    fi
  else
    echo "::warning::无法在 SukiSU 源仓库解析 Release 标签 $TAG"
  fi
else
  # 滚动通道：manager-ci 会替换同分支资产，按 APK 版本反查 main 上对应的提交
  # （提交数是沿历史单调的，用 first-parent 二分查找，找到后校验计数）。
  TARGET_COUNT=$((VERSION - 30000 - 996))
  if [ "$TARGET_COUNT" -gt 0 ]; then
    mapfile -t FIRST_PARENT < <(git -C "$KSU_DIR" rev-list --first-parent origin/main 2>/dev/null || true)
    if [ "${#FIRST_PARENT[@]}" -gt 0 ]; then
      LO=0
      HI=$((${#FIRST_PARENT[@]} - 1))
      while [ "$LO" -le "$HI" ]; do
        MID=$(( (LO + HI) / 2 ))
        CAND="${FIRST_PARENT[$MID]}"
        N=$(git -C "$KSU_DIR" rev-list --count "$CAND" 2>/dev/null || echo 0)
        if [ "$N" -eq "$TARGET_COUNT" ]; then
          COMMIT="$CAND"
          break
        fi
        # 数组从新到旧：计数偏大 → 往更旧找；偏小 → 往更新找
        if [ "$N" -gt "$TARGET_COUNT" ]; then
          LO=$((MID + 1))
        else
          HI=$((MID - 1))
        fi
      done
    fi
  fi
  if [ -z "$COMMIT" ]; then
    echo "::warning::无法将 manager-ci 版本 $VERSION 对齐到 main 提交；内核侧将跟随 main HEAD"
  fi
fi

mkdir -p manager-artifacts
while IFS=$'\t' read -r NAME URL; do
  NAME="${NAME%$'\r'}"
  URL="${URL%$'\r'}"
  curl -fsSL --retry 3 --max-time 300 -o "manager-artifacts/$(basename "$NAME")" "$URL"
done <<< "$ASSETS"
echo "SukiSU-Nova $TAG: 管理器 $VERSION，内核版本来源提交 ${COMMIT:-未锁定}"
echo "MANAGER_VERSION=$VERSION" >> "$GITHUB_ENV"
{
  echo "managerVer=$VERSION"
  echo "ksuCommit=$COMMIT"
  if [ "$ROLLING" = false ]; then
    echo "channelTag=$TAG"
  fi
} >> "$GITHUB_OUTPUT"
