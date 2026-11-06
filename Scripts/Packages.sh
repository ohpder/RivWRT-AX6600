# =========================================================
# RivWRT 外部组件注入清单
# 由 WRT-CORE.yml 在 Custom Packages 阶段调用（cwd = wrt/package/）
#
# 组件（无条件注入，RIVWRT profile）：
#   aurora        eamonxg/luci-theme-aurora        主题
#   athena-led    unraveloop/JDC-AX6600-...        LED 点阵屏（pkg 提取两子包）
#   bandix-plus   timsaya/openwrt-bandix-plus      流量统计后端（pkg）
#   luci-app-bandix-plus  timsaya/luci-app-bandix-plus     统计前端（pkg）
#   dae           kenzok8/openwrt-daede            代理一体包（pkg-exact 提取
#                 dae/daed/luci-app-daede/vmlinux-btf 四子包）
#   partexp       sirpdboy/luci-app-partexp        分区扩容 Web 工具
#   wolultra      ones20250/packages               网络唤醒（pkg-exact）
#   mwan3 / luci-app-mwan3                         双 WAN 组件（当前停用）
#
# 新增组件：仿照下方 UPDATE_PACKAGE 调用（仓库/分支/提取模式），
# 配套 CONFIG_PACKAGE_ 行加到 Config/GENERAL_AX6600_RIVWRT.txt。
# =========================================================
#!/bin/bash

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	# pkg-exact 模式：删除与子目录提取均按第5参精确名匹配。
	# 通配 *dae* 会误删 feeds 里 libdaemon / perl-http-daemon 等名字含 dae 的无关包。
	local PKG_EXACT=0
	if [[ "$PKG_SPECIAL" == "pkg-exact" ]]; then
		PKG_EXACT=1
		PKG_SPECIAL="pkg"
	fi
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS
		if [[ "$PKG_EXACT" == "1" ]]; then
			FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "$NAME" 2>/dev/null)
		else
			FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		fi

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	local PKG_COMMIT
	PKG_COMMIT=$(git -C "$REPO_NAME" rev-parse --short HEAD 2>/dev/null || echo unknown)
	if [ -n "$GITHUB_WORKSPACE" ]; then
		echo "$PKG_NAME $PKG_REPO $PKG_BRANCH $PKG_COMMIT" >> "$GITHUB_WORKSPACE/package-versions.txt"
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 先把仓库目录移到临时名再提取：若仓库名与包子目录同名
		# （如 bandix 两仓 / partexp），cp 目标已存在会把包嵌套复制进自身再被整体删除
		mv "./$REPO_NAME" "./.extract-tmp"
		if [[ "$PKG_EXACT" == "1" ]]; then
			# 按精确名提取仓库内的子目录包
			for NAME in "${PKG_LIST[@]}"; do
				[ -d "./.extract-tmp/$NAME" ] && cp -rf "./.extract-tmp/$NAME" ./ || true
			done
		else
			# 按包名通配提取子目录包
			find "./.extract-tmp"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		fi
		rm -rf "./.extract-tmp"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"
#UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
#UPDATE_PACKAGE "aurora" "ones20250/luci-theme-aurora" "master"
#UPDATE_PACKAGE "aurora-config" "ones20250/luci-app-aurora-config" "master"
#UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
#UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

#UPDATE_PACKAGE "homeproxy" "ones20250/homeproxy" "master"
#UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
#UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
# =========================================================
# RivWRT 组件注入（基于上游纯净版基座的定制组件，无条件拉取）
# 顺序：主题 → LED → bandix → daede
# =========================================================

# RivWRT：LuCI 主题（eamonxg 版 aurora，自带 uci-defaults 首次启动自动激活）
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
# RivWRT：aurora 主题设置界面（5 套预设/自定义色彩/导航布局/主题商店）
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

# RivWRT：LED 点阵屏控制器 —— 使用上游树内官方版
# （package/emortal/luci-app-athena-led，ones20250 官方固件同款，自带预编译二进制零下载）。
# 注：unraveloop 增强版 release 资产（athena-led-*-v2.5.0.tar.gz）已被上游删除，
# 下载 404 无法构建，故回退树内版；其核心同为 haipengno1/athena-led 集成。
# 恢复资产后可换回：UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main" "pkg"

# RivWRT：bandix-plus 流量统计（后端 + LuCI 前端；eBPF 旁路观察，不碰转发路径）
UPDATE_PACKAGE "bandix-plus" "timsaya/openwrt-bandix-plus" "main" "pkg"
UPDATE_PACKAGE "luci-app-bandix-plus" "timsaya/luci-app-bandix-plus" "main" "pkg"

# RivWRT：daede 透明代理一体包。pkg-exact 按精确名提取 4 个子目录包：
# dae（eBPF 内核）/ daed / luci-app-daede / vmlinux-btf（dae/daed 的 BTF 依赖包）；
# 删除 feeds 同名旧包（dae/daed）同样走精确匹配，luci-app-dae/daed 不同名保留无碍。
UPDATE_PACKAGE "dae" "kenzok8/openwrt-daede" "main" "pkg-exact" "dae daed luci-app-daede vmlinux-btf"

# RivWRT：网络唤醒。上游 wolplus 已换代为 wolultra（ones20250/packages 内，依赖 etherwake），
# 从大杂烩仓库精确提取该包
UPDATE_PACKAGE "wolultra" "ones20250/packages" "main" "pkg-exact" "luci-app-wolultra"

#UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"

# RivWRT：分区扩容挂载插件（Web 界面一键格式化/扩容/挂载剩余存储）
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main" "pkg"

# RivWRT：mwan3 多 WAN 负载均衡 / 故障切换
#
# ★★ 版本必须区分清楚，这里用的是 dl12345 的 nftables 移植版，不是 feeds 里的旧版：
#      feeds（immortalwrt/openwrt packages）  mwan3 2.12.2 = iptables + ipset 时代
#      dl12345/mwan3   (openwrt-25.12 分支)   mwan3 3.6.12 = nftables + ucode
#    本固件是 fw4/nftables（树内无 iptables），2.12.2 会拖进整套 iptables 兼容层
#    且与 fw4 争抢 netfilter，因此绝不能用 feeds 里的旧版。
#    3.6.12 已改为独立 `table inet mwan3`（不再侵入 fw4 的 table），这也是新版的行为。
#
#    依赖（15 项）已核对：现有固件已含 12 项；缺的 3 项在树内、由 +DEPENDS 自动拉入 ——
#      libnetfilter-conntrack（package/libs/）· libmnl（被前者 +DEPENDS 带入）
#      ucode-mod-socket（ucode 包的 UcodeModule 宏生成）
#    另 PKG_BUILD_DEPENDS: libnetfilter_conntrack libmnl（构建期，随上面两项进 staging）。
#
#    下行的删除步骤按 *mwan3* 通配扫 feeds，会同时命中 feeds/packages/net/mwan3 与
#    feeds/luci/applications/luci-app-mwan3，正好把旧版清掉（避免同名包双重定义）；
#    它只扫 ../feeds/ 不扫当前目录，故不会误删刚克隆的包。
# Dual WAN 已停用；保留包来源记录，需要恢复时再取消注释。
# UPDATE_PACKAGE "mwan3" "dl12345/mwan3" "openwrt-25.12"
# RivWRT：mwan3 的 LuCI 界面（同作者的 nftables 移植版）
# ★ 必须与后端同源：feeds 里的 luci-app-mwan3 配的是 2.x 的配置结构，
#   与 3.6.12 的后端不匹配。
# UPDATE_PACKAGE "luci-app-mwan3" "dl12345/luci-app-mwan3" "openwrt-25.12"

#UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
#UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
#UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
#UPDATE_PACKAGE "gecoosac" "laipeng668/luci-app-gecoosac" "main"
#UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox speedtest"
#UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
#UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
#UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
#UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
#UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
#局域网唤醒
#UPDATE_PACKAGE "viking" "ones20250/packages" "main" "" "luci-app-timewol luci-app-wolplus"
#UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"
#雅典娜的led屏
#UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"
