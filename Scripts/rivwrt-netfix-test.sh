#!/bin/sh
# RivWRT wan6 修复的回归测试（针对 uci-defaults/98-rivwrt-wan6-fix）。
#
# 用法：  sh Scripts/rivwrt-netfix-test.sh
#
# 被测脚本负责修正 qualcommax 首启时可能生成的不完整 wan6 接口：补齐默认
# device=wan 与 proto=dhcpv6，同时保留用户明确设置的其它 device/proto。
#
# 做法：从 Settings.sh 的 heredoc 里【按标记抽取】脚本原文，配合 mock uci 执行。
# 测的就是要上机跑的代码；标记改名会直接报错，不会静默通过。
#
# ★ 写 mock uci 的坑（本测试踩过，值得记住）：
#   函数末尾【不能】写 `return 0`。被测脚本靠 `uci -q get <key>` 的成功/失败
#   来判断 section 是否存在，无条件 return 0 会把"不存在"也判成存在，于是
#   迁移分支全被跳过 —— 测试看着"通过"，实际什么都没验。mock 必须复刻真实
#   的退出码语义。
# ★ 另一坑：mock 里删旧键若用 `grep -v "^$key="`，键中的 uci 匿名段语法
#   `[0]` 会被 grep 当字符类（只匹配 "0"），旧行删不掉、新行追加成第二份，
#   读回时取到旧值。故改用 awk 按字段精确比较。

set -u

# 路径形态注意：本仓库在 Windows(MSYS) 下开发时，pwd 返回的是【反斜杠】形式
# 的盘符路径。这种路径若直接用于 shell 中点号加载，反斜杠会被当作转义符 ——
# 结果是静默失败：不报错、脚本根本没执行，测试却显示"跑过了"。
# 统一归一化成正斜杠，避免这个坑。
HERE=$(dirname "$0"); HERE=$(cd "$HERE" && pwd | tr '\\\\' '/')
SH="$HERE/Settings.sh"
MOCK="$HERE/.netfix-test.$$"
CFG="$MOCK/uci.db"
mkdir -p "$MOCK"
# 清理临时目录。**不要 trap PIPE**：被测脚本内部有产生大量输出的命令，
# 一旦管子被截断就会收到 SIGPIPE，把 trap 当成退出信号，脚本会中途停止
# （表现为"测试没跑完、也没有断言输出"，极难察觉）。EXIT 已覆盖正常与中断退出。
trap 'rm -rf "$MOCK"' EXIT INT TERM HUP

[ -f "$SH" ] || { echo "找不到 $SH"; exit 1; }

# ── 从 Settings.sh 抽取 uci-defaults 脚本正文 ──
SCRIPT="$MOCK/netfix.sh"
awk '
	/cat > "\$UDIR\/98-rivwrt-wan6-fix" <<.RIVWRT_WAN6./ { f = 1; next }
	f && /^RIVWRT_WAN6$/ { exit }
	f { print }
' "$SH" > "$SCRIPT"

[ -s "$SCRIPT" ] || { echo "✗ 未能从 Settings.sh 提取 98-rivwrt-wan6-fix（heredoc 标记变了？）"; exit 1; }
grep -q 'network\.wan6' "$SCRIPT" || { echo "✗ 提取内容与预期不符"; exit 1; }

# ── mock uci：配置存为 key=value 行 ──
uci() {
	# shift 掉 -q 后：$1 是动作名，$2 是键（get）或 key=value（set/rename）
	if [ "$1" = "-q" ]; then shift; fi
	case "$1" in
	get)
		awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$CFG"
		# 退出码决定"该键是否存在"，必须如实反映
		awk -F= -v k="$2" '$1==k{f=1}END{exit !f}' "$CFG"
		;;
	set)
		kv="$2"; key="${kv%%=*}"; val="${kv#*=}"
		awk -F= -v k="$key" '$1 != k' "$CFG" > "$CFG.t" 2>/dev/null
		mv "$CFG.t" "$CFG" 2>/dev/null
		printf '%s=%s\n' "$key" "$val" >> "$CFG"
		;;
	rename)
		# uci rename <cfg>.<section>=<newsection>：只换最后一段 section 名
		old="${2%%=*}"; new="${2#*=}"
		prefix="${old%.*}"; newfull="$prefix.$new"
		sed -i "s|^$old\.|$newfull.|; s|^$old=|$newfull=|" "$CFG"
		;;
	commit) : ;;
	esac
	# 不写 return 0：让 case 分支最后一条命令的退出码作为返回值
}

FAILED=0
ck() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1  [期望 '$3' 实际 '$2']"; FAILED=$((FAILED + 1)); fi }
run() { . "$SCRIPT" >/dev/null 2>&1; }

echo "───────── 场景 A：缺少 wan6 时创建默认 IPv6 上行─────────"
cat > "$CFG" <<'EOF'
network.wan=interface
network.wan.device=wan
EOF
run
ck "创建 wan6 接口" "$(uci -q get network.wan6)" "interface"
ck "默认 device 指向 wan" "$(uci -q get network.wan6.device)" "wan"
ck "默认 proto 为 dhcpv6" "$(uci -q get network.wan6.proto)" "dhcpv6"

echo ""
echo "───────── 场景 B：已有空壳时补齐字段─────────"
cat > "$CFG" <<'EOF'
network.wan=interface
network.wan.device=wan
network.wan6=interface
network.wan6.proto=none
EOF
run
ck "空 device 补为 wan" "$(uci -q get network.wan6.device)" "wan"
ck "none proto 补为 dhcpv6" "$(uci -q get network.wan6.proto)" "dhcpv6"

echo ""
echo "───────── 场景 C：旧 wan1/wan2 device 迁到单 WAN─────────"
cat > "$CFG" <<'EOF'
network.wan=interface
network.wan.device=wan
network.wan6=interface
network.wan6.device=wan2
network.wan6.proto=dhcpv6
EOF
run
ck "旧 device 迁到 wan" "$(uci -q get network.wan6.device)" "wan"
ck "已有 proto 保留" "$(uci -q get network.wan6.proto)" "dhcpv6"

echo ""
echo "───────── 场景 D：保留用户设置的有效配置─────────"
cat > "$CFG" <<'EOF'
network.wan6=interface
network.wan6.device=eth0
network.wan6.proto=static
EOF
run
ck "自定义 device 不覆盖" "$(uci -q get network.wan6.device)" "eth0"
ck "自定义 proto 不覆盖" "$(uci -q get network.wan6.proto)" "static"

echo ""
echo "───────── 场景 E：幂等─────────"
run
ck "device 二次执行保持" "$(uci -q get network.wan6.device)" "eth0"
ck "proto 二次执行保持" "$(uci -q get network.wan6.proto)" "static"

echo ""
echo "───────── 场景 F：仅迁移旧双 WAN device 名─────────"
cat > "$CFG" <<'EOF'
network.wan6=interface
network.wan6.device=wan1
network.wan6.proto=dhcpv6
EOF
run
ck "旧 device 迁到 wan" "$(uci -q get network.wan6.device)" "wan"
ck "已有 proto 保留" "$(uci -q get network.wan6.proto)" "dhcpv6"

echo ""
if [ "$FAILED" -eq 0 ]; then
	echo "✅ 全部通过"
else
	echo "❌ 失败 $FAILED 项"
	exit 1
fi
