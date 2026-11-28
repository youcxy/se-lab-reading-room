#!/usr/bin/env bash
# =============================================================================
# 本地（Windows Git Bash）打包 + 上传 + 触发 ECS 部署 —— 密码登录版
#
# 适用：用「快速配置」页买的 ECS（该页没有「登录凭证/密钥对」选项），
#       创建后已在 ECS 控制台「更多 -> 重置密码」设置过 root 密码。
#
# 用法：
#   bash deploy/pack_for_ecs_pwd.sh <ECS公网IP> [FG_ENDPOINT]
# 例：
#   bash deploy/pack_for_ecs_pwd.sh 122.9.9.229
#
# 注意：
#   - scp 和 ssh 会各提示输入一次 root 密码，共 2 次（正常现象）
#   - 安全组需放行 TCP 22；默认 Sys-WebServer 安全组已包含
#   - 重复执行会保留已初始化的数据库，不会清空演示数据
# =============================================================================
set -euo pipefail

EIP="${1:-}"
FG_ENDPOINT="${2:-}"

if [[ -z "$EIP" ]]; then
  echo "用法: bash deploy/pack_for_ecs_pwd.sh <ECS公网IP> [FG_ENDPOINT]" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
NODE="$(command -v node || true)"
[[ -n "$NODE" ]] || { echo '找不到 node，请用 Git Bash 并确保 node 在 PATH' >&2; exit 1; }

echo '[1/5] 重新构建前端 dist ...'
(cd frontend/reading-room-front && "$NODE" node_modules/vite/bin/vite.js build)
[[ -f frontend/reading-room-front/dist/index.html ]] || { echo '前端构建失败' >&2; exit 1; }

echo '[2/5] 组装部署目录 ...'
STAGE=/tmp/studyroom
rm -rf "$STAGE"
mkdir -p "$STAGE"/{backend,frontend,sql,deploy,scripts} \
         "$STAGE"/cloud/functiongraph/{billing,timeout_release}
cp backend/target/studyroom-backend-1.0.0.jar "$STAGE/backend/"
cp -r frontend/reading-room-front/dist/. "$STAGE/frontend/"
cp sql/init.sql sql/test_data.sql "$STAGE/sql/"
cp deploy/nginx.conf deploy/ecs_setup.sh deploy/setup_aksk.sh deploy/cloud.env.example "$STAGE/deploy/"
cp scripts/mock_fg.py "$STAGE/scripts/"
# mock_fg.py 会 import billing / timeout_release，必须按相对路径带上这两个 handler
cp cloud/functiongraph/billing/billing.py "$STAGE/cloud/functiongraph/billing/"
cp cloud/functiongraph/timeout_release/timeout_release.py "$STAGE/cloud/functiongraph/timeout_release/"
tar -czf /tmp/studyroom-ecs.tar.gz -C /tmp studyroom
ls -lh /tmp/studyroom-ecs.tar.gz

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o PreferredAuthentications=password -o PubkeyAuthentication=no
          -o ServerAliveInterval=30 -o ConnectTimeout=15)

echo "[3/5] 上传到 root@$EIP（此处输入第 1 次 root 密码）..."
# -O: legacy SCP 协议，避免新 OpenSSH 的 SFTP 大文件被中途断流
scp -O "${SSH_OPTS[@]}" /tmp/studyroom-ecs.tar.gz "root@$EIP:/tmp/"

echo '[4/5] 在 ECS 上执行部署（装 JDK21/MySQL/nginx 约 3-8 分钟，请勿关闭窗口；此处输入第 2 次 root 密码）...'
REMOTE='set -e
KEEP=0
[ -f /opt/studyroom/.db_initialized ] && KEEP=1
rm -rf /opt/studyroom
tar -xzf /tmp/studyroom-ecs.tar.gz -C /opt
[ "$KEEP" -eq 1 ] && touch /opt/studyroom/.db_initialized
chmod +x /opt/studyroom/deploy/ecs_setup.sh
'
if [[ -n "$FG_ENDPOINT" ]]; then
  ssh "${SSH_OPTS[@]}" "root@$EIP" "$REMOTE FG_ENDPOINT='$FG_ENDPOINT' bash /opt/studyroom/deploy/ecs_setup.sh"
else
  ssh "${SSH_OPTS[@]}" "root@$EIP" "$REMOTE bash /opt/studyroom/deploy/ecs_setup.sh"
fi

echo '[5/5] 本地验证公网访问 ...'
curl -s --noproxy '*' --max-time 20 -o /dev/null -w "首页 HTTP %{http_code}\n" "http://$EIP/"
curl -s --noproxy '*' --max-time 20 "http://$EIP/api/health"; echo
echo
echo '下一步：把云函数 seat-scan-func 的环境变量 BACKEND_BASE 改成'
echo "        http://$EIP"
echo '        然后在 FunctionGraph 控制台点「测试」，期望 statusCode:200 / handled:0'
