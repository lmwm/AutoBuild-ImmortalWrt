#!/bin/sh
# IPv6 状态监控 + 主动探活
# 目的：IPv6 出问题时自动抓取现场变量，避免人工采样时状态已变化
# 部署位置：路由器 /root/v6mon/w.sh
# 日志：/root/v6mon/log.txt（每分钟一条，按天滚动到 log-YYYYMMDD.txt）

LOG_DIR="/root/v6mon"
LOG="$LOG_DIR/log.txt"
STATE="$LOG_DIR/last_state.txt"

# 探活目标：FNOS（下游设备，最关键的判据）
# 用 MAC 动态查找，避免前缀变化后硬编码地址失效
FNOS_MAC="7c:83:34:b7:ca:26"
fnos_addr() {
    ip -6 neigh show dev br-lan 2>/dev/null \
      | awk -v m="$FNOS_MAC" '$0 ~ m && $1 != "fe80:" && $0 !~ /^fe80/ {print $1; exit}'
}
# 外网探活目标（多个，避免单个目标本身故障造成误判）
PROBE_EXT1="2400:3200::1"
PROBE_EXT2="240e:56:4000::218"

mkdir -p "$LOG_DIR"

# 按天滚动
rotate() {
    TODAY=$(date +%Y%m%d)
    if [ -f "$LOG_DIR/.lastday" ]; then
        LAST=$(cat "$LOG_DIR/.lastday" 2>/dev/null)
        if [ "$LAST" != "$TODAY" ] && [ -f "$LOG" ]; then
            mv "$LOG" "$LOG_DIR/log-$LAST.txt"
        fi
    fi
    echo "$TODAY" > "$LOG_DIR/.lastday"
}

while true; do
    rotate
    TS=$(date "+%Y-%m-%d %H:%M:%S")

    # --- 路由器自身状态 ---
    GW=$(ip -6 route show default 2>/dev/null | sed -n 's/.*via \([0-9a-f:]*\).*/\1/p' | head -1)
    GW_REACH="no"
    if [ -n "$GW" ]; then
        ping6 -c1 -W2 "$GW%usb0" >/dev/null 2>&1 && GW_REACH="yes"
    fi

    USB0_ADDR=$(ip -6 addr show usb0 2>/dev/null | grep 'scope global' | awk '{print $2}' | head -1)
    USB0_PREFIX=$(echo "$USB0_ADDR" | cut -d: -f1-4)

    BRLAN_G=$(ip -6 addr show br-lan 2>/dev/null | grep -c 'scope global')
    BHLINE=$(ip -6 route show table main 2>/dev/null | grep 'unreachable' | head -1)
    BH=${BHLINE:+1}; [ -z "$BH" ] && BH=0

    # --- RA/RS 计数（核心判据）---
    U_RS=$(awk '/Icmp6OutRouterSolicits/{print $2}' /proc/net/dev_snmp6/usb0 2>/dev/null)
    U_RA=$(awk '/Icmp6InRouterAdvertisements/{print $2}' /proc/net/dev_snmp6/usb0 2>/dev/null)
    B_ORA=$(awk '/Icmp6OutRouterAdvertisements/{print $2}' /proc/net/dev_snmp6/br-lan 2>/dev/null)
    B_IRS=$(awk '/Icmp6InRouterSolicits/{print $2}' /proc/net/dev_snmp6/br-lan 2>/dev/null)

    # --- proxy NDP ---
    PX=$(ip -6 neigh show proxy 2>/dev/null | wc -l)
    PX_FAIL=$(ip -6 neigh show 2>/dev/null | grep -c 'FAILED')

    # --- 中继状态自愈：proxy_ndp 丢失时重启 odhcpd ---
    # 背景：WAN 链路抖动/设备重建会把 usb0 的 proxy_ndp 复位为 0，
    #       odhcpd 不会自动重设，外网入站到 LAN 设备的 NDP 解析会失败。
    #       详见 Guides/CPE_MF650_IPV6_MODEM_APP.md §9。
    PN=$(cat /proc/sys/net/ipv6/conf/usb0/proxy_ndp 2>/dev/null)
    if [ "$PN" != "1" ]; then
        NOW=$(date +%s)
        LAST=$(cat "$LOG_DIR/.last_heal" 2>/dev/null)
        [ -z "$LAST" ] && LAST=0
        if [ $((NOW - LAST)) -ge 300 ]; then
            echo "$NOW" > "$LOG_DIR/.last_heal"
            logger -t v6mon "self-heal: usb0 proxy_ndp=$PN, restarting odhcpd"
            /etc/init.d/odhcpd restart
            echo "$TS | SELF-HEAL: usb0 proxy_ndp=$PN -> odhcpd restarted" >> "$LOG"
        fi
    fi

    # --- 主动探活 ---
    P_FNOS="no-addr"
    FHOST=$(fnos_addr)
    if [ -n "$FHOST" ]; then
        P_FNOS="fail"
        ping6 -c1 -W2 "$FHOST" >/dev/null 2>&1 && P_FNOS="ok"
    fi
    P_EXT="fail"
    ping6 -c1 -W2 "$PROBE_EXT1" >/dev/null 2>&1 && P_EXT="ok"
    [ "$P_EXT" = "fail" ] && { ping6 -c1 -W2 "$PROBE_EXT2" >/dev/null 2>&1 && P_EXT="ok"; }

    # --- 下游邻居表统计 ---
    NB_TOTAL=$(ip -6 neigh show dev br-lan 2>/dev/null | wc -l)
    NB_FAIL=$(ip -6 neigh show dev br-lan 2>/dev/null | grep -c 'FAILED')

    LINE="$TS | ext=$P_EXT fnos=$P_FNOS | gw=$GW($GW_REACH) | usb0=$USB0_PREFIX blg=$BRLAN_G bh=$BH | RS=$U_RS RA=$U_RA brORA=$B_ORA brIRS=$B_IRS | px=$PX pxfail=$PX_FAIL nb=$NB_TOTAL nbfail=$NB_FAIL"

    echo "$LINE" >> "$LOG"

    # --- 异常时额外抓取现场快照 ---
    if [ "$P_EXT" = "fail" ] || [ "$P_FNOS" = "fail" ]; then
        SNAP="$LOG_DIR/anomaly-$(date +%Y%m%d-%H%M%S).txt"
        {
            echo "========== 异常快照 $TS =========="
            echo "--- 判据 ---"
            echo "ext=$P_EXT fnos=$P_FNOS"
            echo "--- default route ---"
            ip -6 route show default
            echo "--- 全部 IPv6 路由（滤 kernel/multicast）---"
            ip -6 route show table all | grep -vE 'proto kernel|ff00|local|::1'
            echo "--- usb0 地址 ---"
            ip -6 addr show usb0
            echo "--- br-lan 地址 ---"
            ip -6 addr show br-lan
            echo "--- usb0 邻居 ---"
            ip -6 neigh show dev usb0
            echo "--- br-lan 邻居 ---"
            ip -6 neigh show dev br-lan
            echo "--- proxy NDP ---"
            ip -6 neigh show proxy
            echo "--- RA/RS 计数 ---"
            echo "usb0: RS=$U_RS RA=$U_RA"
            echo "br-lan: OutRA=$B_ORA InRS=$B_IRS"
            echo "--- WAN_LTE_IPV6 ubus 状态 ---"
            ubus call network.interface.WAN_LTE_IPV6 status 2>/dev/null
            echo "--- odhcpd 进程 ---"
            ps | grep '[o]dhcpd'
            echo "--- 最近 odhcpd 日志 ---"
            logread 2>/dev/null | grep -iE 'odhcpd|netifd.*ipv6|delegat' | tail -30
        } > "$SNAP" 2>&1
        # 避免刷屏：只在状态由正常转异常时记录一条提示
        PREV=$(cat "$STATE" 2>/dev/null)
        if [ "$PREV" != "anomaly" ]; then
            echo "!!! 检测到异常，已保存快照: $SNAP" >> "$LOG"
            logger -t v6mon "IPv6 anomaly detected, snapshot saved: $SNAP"
        fi
        echo "anomaly" > "$STATE"
    else
        echo "ok" > "$STATE"
    fi

    sleep 60
done
