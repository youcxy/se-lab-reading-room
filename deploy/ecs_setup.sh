#!/usr/bin/env bash
# =============================================================================
# 智能共享自习室管理系统 - 华为云 ECS 一键部署脚本（在 ECS 上以 root 执行）
#
# 前提（由 pack_for_ecs.sh 完成）：文件已放在 /opt/studyroom/
#   backend/studyroom-backend-1.0.0.jar
#   frontend/                (vite build 出来的 dist 内容)
#   sql/init.sql  sql/test_data.sql
#   deploy/nginx.conf  deploy/ecs_setup.sh
#   scripts/mock_fg.py
#
# 用法：
#   sudo bash /opt/studyroom/deploy/ecs_setup.sh
#   sudo FG_ENDPOINT=https://你的APIG调用URL bash /opt/studyroom/deploy/ecs_setup.sh
#
# 说明：
#   - 默认 FG_ENDPOINT 指向本机 mock_fg.py(9100)，保证页面「来源 CLOUD」可用。
#   - 「真·云端」计费推荐走 AK/SK 直调 FunctionGraph（免费、无需 APIG）：
#     填 /etc/studyroom/cloud.env 后重启 studyroom 即可；该文件不会被本脚本覆盖。
#   - 也可把 FG_ENDPOINT 改成 APIG 触发器调用 URL（需付费购买专享版实例）。
#   - 幂等：数据库只在首次初始化（标记文件 .db_initialized），重跑不会清演示数据。
#   - 建议 ECS 规格 2vCPU/4GiB（1GiB 跑 JDK21 + MySQL8 容易 OOM）。
# =============================================================================
set -euo pipefail

APP=/opt/studyroom
DB_USER=study
DB_PASS='Study@123456'
FG_ENDPOINT="${FG_ENDPOINT:-http://127.0.0.1:9100/billing}"
STAMP="$APP/.db_initialized"

info() { printf '\033[36m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die '请用 sudo 运行：sudo bash /opt/studyroom/deploy/ecs_setup.sh'
[[ -f "$APP/backend/studyroom-backend-1.0.0.jar" ]] || die "缺少 $APP/backend/studyroom-backend-1.0.0.jar"
[[ -f "$APP/frontend/index.html" ]]                || die "缺少 $APP/frontend/index.html（前端 dist）"
[[ -f "$APP/sql/init.sql" ]]                        || die "缺少 $APP/sql/init.sql"
[[ -f "$APP/deploy/nginx.conf" ]]                   || die "缺少 $APP/deploy/nginx.conf"

. /etc/os-release
OS_ID="${ID:-unknown}"
info "检测到系统：$OS_ID ${VERSION_ID:-}"
info "FG_ENDPOINT = $FG_ENDPOINT"

# ---------------------------------------------------------------------------
# 1. 安装 JDK 21 / MySQL / nginx / python3
# ---------------------------------------------------------------------------
info '[1/7] 安装依赖（JDK21、MySQL、nginx、python3）...'
case "$OS_ID" in
  ubuntu|debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl nginx python3 ca-certificates || die '基础包安装失败'
    apt-get install -y -qq openjdk-21-jdk-headless 2>/dev/null || info '源里没有 openjdk-21，稍后走镜像兜底'
    apt-get install -y -qq mysql-server 2>/dev/null || apt-get install -y -qq mariadb-server 2>/dev/null || die '数据库安装失败'
    ;;
  rocky|rhel|centos|almalinux|openEuler|euleros)
    PKG=dnf
    command -v dnf >/dev/null 2>&1 || PKG=yum
    $PKG install -y -q curl nginx python3 ca-certificates || die '基础包安装失败'
    $PKG install -y -q java-21-openjdk-headless 2>/dev/null || info '源里没有 java-21，稍后走镜像兜底'
    $PKG install -y -q mysql-server 2>/dev/null || $PKG install -y -q mariadb-server 2>/dev/null || die '数据库安装失败'
    ;;
  *) die "未适配的系统：$OS_ID（推荐 Ubuntu 22.04；也支持 Rocky 9 / EulerOS）" ;;
esac

JAVA_BIN="$(command -v java || true)"
if [[ -z "$JAVA_BIN" ]] || ! "$JAVA_BIN" -version 2>&1 | grep -q 'version "21'; then
  info '从华为云镜像下载 OpenJDK 21（约 200MB）...'
  curl -fL --retry 2 --max-time 600 -o /tmp/jdk21.tar.gz \
    https://repo.huaweicloud.com/openjdk/21/openjdk-21_linux-x64_bin.tar.gz
  mkdir -p /opt/jdk21
  tar -xzf /tmp/jdk21.tar.gz -C /opt/jdk21 --strip-components=1
  printf 'export JAVA_HOME=/opt/jdk21\nexport PATH=$JAVA_HOME/bin:$PATH\n' > /etc/profile.d/jdk21.sh
  JAVA_BIN=/opt/jdk21/bin/java
fi
"$JAVA_BIN" -version 2>&1 | head -1
ok 'JDK 21 就绪'

for svc in mysql mysqld mariadb; do
  if systemctl enable --now "$svc" >/dev/null 2>&1; then ok "数据库服务已启动：$svc"; break; fi
done
for i in $(seq 1 20); do
  mysqladmin ping >/dev/null 2>&1 && break
  sleep 2
done
mysqladmin ping >/dev/null 2>&1 || die 'MySQL 没起来，检查 systemctl status mysql'

# ---------------------------------------------------------------------------
# 2. 建库 + 应用账号（init.sql 只建库建表，不建账号）
# ---------------------------------------------------------------------------
info '[2/7] 初始化数据库 reading_room ...'
mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON reading_room.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
if [[ ! -f "$STAMP" ]]; then
  mysql --default-character-set=utf8mb4 -u root < "$APP/sql/init.sql"
  touch "$STAMP"
  ok 'init.sql 已执行（10 座位、7 账号、单价 4.00）'
else
  ok '数据库已初始化过，跳过 init.sql（保留演示数据）'
fi
SEATS="$(mysql -u "$DB_USER" -p"$DB_PASS" -D reading_room -N -B -e 'SELECT COUNT(*) FROM seat;' 2>/dev/null || echo 0)"
if [[ "$SEATS" == "10" ]]; then ok 'study 账号可连库，座位表 10 行'; else info "警告：座位表查到 $SEATS 行，请检查 init.sql"; fi

# ---------------------------------------------------------------------------
# 3. 前端静态文件 + nginx 反向代理
# ---------------------------------------------------------------------------
info '[3/7] 配置 nginx（静态前端 + /api 反代到 8080）...'
rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
cp "$APP/deploy/nginx.conf" /etc/nginx/conf.d/studyroom.conf
nginx -t || die 'nginx 配置校验失败'
systemctl enable --now nginx >/dev/null 2>&1 || true
systemctl reload nginx
ok 'nginx 已生效（监听 80）'

# ---------------------------------------------------------------------------
# 4. 云函数模拟器（保证页面「来源 CLOUD」与本机一致，可随时停用）
# ---------------------------------------------------------------------------
info '[4/7] 配置本地云函数模拟器 mock_fg（9100）...'
PY_BIN="$(command -v python3)"
cat > /etc/systemd/system/studyroom-mockfg.service <<EOF
[Unit]
Description=Local FunctionGraph simulator (demo fallback)
After=network.target

[Service]
WorkingDirectory=$APP
ExecStart=$PY_BIN $APP/scripts/mock_fg.py 9100
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now studyroom-mockfg >/dev/null 2>&1 || true
sleep 1
if curl -fsS --max-time 5 http://127.0.0.1:9100/health; then
  ok '模拟器已就绪'
else
  info '警告：模拟器未就绪，页面「来源」会变成 LOCAL；用 systemctl status studyroom-mockfg 排查'
fi

# ---------------------------------------------------------------------------
# 5. 后端 systemd 服务
# ---------------------------------------------------------------------------
info '[5/7] 配置并启动 Spring Boot 后端（8080）...'

# AK/SK 只放在 ECS 本机的环境文件里（权限 600），绝不进代码仓库。
# 已存在时不覆盖，避免重跑部署脚本清掉用户填好的密钥。
mkdir -p /etc/studyroom
if [ ! -f /etc/studyroom/cloud.env ]; then
cat > /etc/studyroom/cloud.env <<'ENV'
# FunctionGraph AK/SK 直调配置：仅保存在本 ECS，权限 600，禁止写入仓库。
# 全部留空 -> 后端走 HTTP 端点（默认本机模拟器）；填齐下面 4 项 -> 页面来源为华为云真算的 CLOUD。
FG_SDK_AK=
FG_SDK_SK=
FG_SDK_PROJECT_ID=
FG_SDK_FUNCTION_NAME=
# 也可直接粘贴控制台的完整函数 URN（优先于 FG_SDK_FUNCTION_NAME）：
# FG_SDK_FUNCTION_URN=urn:fss:cn-north-4:<projectId>:function:default:billing-func:latest
FG_SDK_REGION=cn-north-4
ENV
fi
chmod 600 /etc/studyroom/cloud.env

cat > /etc/systemd/system/studyroom.service <<EOF
[Unit]
Description=Smart Reading Room Backend
After=network.target mysql.service mysqld.service mariadb.service

[Service]
Type=simple
WorkingDirectory=$APP/backend
EnvironmentFile=-/etc/studyroom/cloud.env
Environment=FG_ENDPOINT=$FG_ENDPOINT
Environment=STUDY_DB_USER=$DB_USER
Environment=STUDY_DB_PASSWORD=$DB_PASS
ExecStart=$JAVA_BIN -Dfile.encoding=UTF-8 -Xms256m -Xmx768m -jar $APP/backend/studyroom-backend-1.0.0.jar
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now studyroom >/dev/null 2>&1 || true

info '等待后端启动（最多 60 秒）...'
for i in $(seq 1 30); do
  curl -fsS --max-time 3 http://127.0.0.1:8080/api/health >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS --max-time 5 http://127.0.0.1:8080/api/health || die '后端没起来：journalctl -u studyroom -n 50'
ok '后端已就绪'

# ---------------------------------------------------------------------------
# 6. 自检
# ---------------------------------------------------------------------------
info '[6/7] 端到端自检...'
printf '  首页(80)        : '; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 http://127.0.0.1/ || true
printf '  /api/health(80) : '; curl -s --max-time 8 http://127.0.0.1/api/health || true; echo
printf '  云端计费        : '; curl -s --max-time 8 -X POST -H 'Content-Type: application/json' \
  -d '{"unitPrice":4.00,"minutes":30}' http://127.0.0.1/api/cloud/quote || true; echo
printf '  计费通路        : '; curl -s --max-time 8 http://127.0.0.1/api/cloud/status || true; echo
printf '  定时释放        : '; curl -s --max-time 8 -X POST -H 'Content-Type: application/json' \
  -d '{}' http://127.0.0.1/api/timeout/run || true; echo

# ---------------------------------------------------------------------------
# 7. 收尾提示
# ---------------------------------------------------------------------------
info '[7/7] 部署完成。接下来在华为云控制台做 3 件事：'
cat <<'NEXT'
  1) 安全组入方向放行 TCP 22（部署脚本 scp/ssh 用）和 TCP 80（页面用）；
     8080/9100/3306 不要对公网开放。默认 Sys-WebServer 安全组已含 22/80。
  2) FunctionGraph -> seat-scan-func -> 环境变量 BACKEND_BASE 改成
         http://<本ECS的弹性公网IP>
     （不带结尾斜杠、不带 8080 端口，nginx 会在 80 上反代 /api）
     然后点「测试」，期望 statusCode:200 / handled:0。
  3) 若要页面显示「真·云端」计费（不用买 APIG）：在 IAM 建一次访问密钥，
     填入 /etc/studyroom/cloud.env 的 FG_SDK_AK / FG_SDK_SK / FG_SDK_PROJECT_ID /
     FG_SDK_FUNCTION_NAME（或完整 URN），然后：
         sudo systemctl restart studyroom
         curl http://127.0.0.1/api/cloud/status   # 应显示 FUNCTIONGRAPH_AKSK
     未填时默认是本机 mock_fg 模拟器，页面也会显示 CLOUD 但不是华为云真算的。
     密钥只存本 ECS，删机前记得清空该文件。

  本机自查：浏览器打开 http://<弹性公网IP>/ 应能看到登录页。
  常用排错：systemctl status studyroom / journalctl -u studyroom -n 50
            systemctl status nginx     / tail -50 /var/log/nginx/error.log
NEXT
ok '全部完成'
