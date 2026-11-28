#!/usr/bin/env bash
# =============================================================================
# 本地（Windows Git Bash）打包 + 上传 + 触发 ECS 部署
#
# 用法：
#   bash deploy/pack_for_ecs.sh <ECS公网IP> <密钥.pem的POSIX路径> [FG_ENDPOINT]
# 例：
#   bash deploy/pack_for_ecs.sh 122.9.9.229 /c/Users/uccen/Downloads/ecs_key.pem
#   bash deploy/pack_for_ecs.sh 122.9.9.229 /c/Users/uccen/Downloads/ecs_key.pem \
#        https://xxxx.apig.cn-north-4.huaweicloud.com/billing
#
# 注意：
#   - Windows 路径要写成 Git Bash 形式（C:\Users\x -> /c/Users/x）
#   - 不传 FG_ENDPOINT 时，ECS 上默认用本机 mock_fg 模拟器（页面显示 CLOUD）
#   - 重复执行会保留已初始化的数据库，不会清空演示数据
# =============================================================================
set -euo pipefail

EIP="${1:-}"
KEY="${2:-}"
FG_ENDPOINT="${3:-}"

if [[ -z "$EIP" || -z "$KEY" ]]; then
  echo "用法: bash deploy/pack_for_ecs.sh <ECS公网IP> <密钥.pem> [FG_ENDPOINT]" >&2
  exit 1
fi
[[ -f "$KEY" ]] || { echo "找不到密钥文件：$KEY" >&2; exit 1; }
chmod 600 "$KEY" 2>/dev/null || true

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

echo "[3/5] 上传到 root@$EIP ..."
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ConnectTimeout=15)
# -O: 强制使用 legacy SCP 协议。新 OpenSSH 默认走 SFTP，部分网络/代理环境下
#     传输 20MB+ 文件会被 "Connection closed by <ip> port 22" 中断（实测华为云 ECS）。
scp -O "${SSH_OPTS[@]}" /tmp/studyroom-ecs.tar.gz "root@$EIP:/tmp/"

echo '[4/5] 在 ECS 上执行部署（装 JDK21/MySQL/nginx 约 3-8 分钟，请勿关闭窗口）...'
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
