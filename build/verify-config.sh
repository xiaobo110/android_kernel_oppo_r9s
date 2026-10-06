#!/usr/bin/env bash
# 校验合并后的 .config。
# 逻辑：先看符号在这棵树里到底存不存在（grep Kconfig），存在却没打开 = 硬失败；
# 不存在（本树没有该特性）= 只报告，避免白烧一轮 CI。
set -u
CFG="${1:-out/.config}"
TREE="${2:-.}"
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }

REQUIRED="NAMESPACES UTS_NS IPC_NS PID_NS NET_NS USER_NS KEYS POSIX_MQUEUE SYSVIPC \
SECCOMP SECCOMP_FILTER CGROUPS CGROUP_FREEZER CGROUP_CPUACCT CGROUP_SCHED CPUSETS \
FAIR_GROUP_SCHED CFS_BANDWIDTH RT_GROUP_SCHED BLK_CGROUP MEMCG MEMCG_SWAP OVERLAY_FS \
BRIDGE BRIDGE_NETFILTER VETH IPVLAN MACVLAN DUMMY TUN DEVPTS_MULTIPLE_INSTANCES \
NF_CONNTRACK NF_CONNTRACK_IPV4 NF_NAT NF_NAT_IPV4 IP_NF_IPTABLES IP_NF_FILTER IP_NF_NAT \
IP_NF_TARGET_MASQUERADE NETFILTER_XT_MATCH_ADDRTYPE NETFILTER_XT_MATCH_CONNTRACK \
NETFILTER_XT_MATCH_COMMENT NETFILTER_XT_TARGET_MASQUERADE NETFILTER_XT_SET \
EXT4_FS EXT4_FS_POSIX_ACL \
TMPFS TMPFS_POSIX_ACL PRONTO_WLAN"

NICE="CGROUP_PIDS CGROUP_DEVICE CGROUP_NET_PRIO CGROUP_NET_CLASSID CGROUP_PERF \
CGROUP_HUGETLB MEMCG_KMEM MEMCG_SWAP_ENABLED BLK_DEV_THROTTLING BRIDGE_VLAN_FILTERING \
VXLAN NETFILTER_XT_MATCH_PHYSDEV NETFILTER_XT_MATCH_BPF NETFILTER_XT_MATCH_IPVS IP_SET \
IP_SET_HASH_IP IP_SET_HASH_NET IKCONFIG IKCONFIG_PROC TMPFS_XATTR CONFIGFS_FS \
IP6_NF_IPTABLES IP6_NF_NAT IP_NF_TARGET_REDIRECT INET_ESP XFRM_USER CRYPTO_GCM \
IOSCHED_CFQ CFQ_GROUP_IOSCHED NET_CLS_CGROUP IP_VS BLK_DEV_DM DM_THIN_PROVISIONING \
AUFS_FS BTRFS_FS CGROUP_BPF SECURITY_APPARMOR"

# 一次性把所有 Kconfig 里的符号名抓出来，避免每个符号全树扫一遍
SYMS=$(mktemp)
grep -rhoE "^config [A-Z0-9_]+" --include=Kconfig --include='Kconfig*' \
     --exclude-dir=.git --exclude-dir=out "$TREE" 2>/dev/null | awk '{print $2}' | sort -u > "$SYMS"
echo "tree defines $(wc -l < "$SYMS") kconfig symbols"

has_symbol() { grep -cx "$1" "$SYMS" >/dev/null; }

fail=0
for s in $REQUIRED; do
  if ! has_symbol "$s"; then
    echo "NO SUCH SYMBOL in this tree: CONFIG_$s  (特性本身不存在，跳过)"
    continue
  fi
  if ! grep -qE "^CONFIG_$s=[ym]$" "$CFG"; then
    echo "MISSING REQUIRED: CONFIG_$s"
    fail=1
  fi
done

if grep -qE "^CONFIG_ANDROID_PARANOID_NETWORK=y$" "$CFG"; then
  echo "STILL ON: CONFIG_ANDROID_PARANOID_NETWORK (容器内无法建 socket)"
  fail=1
fi

echo "--- 理想但可选 ---"
for s in $NICE; do
  if grep -qE "^CONFIG_$s=[ym]$" "$CFG"; then :;
  elif has_symbol "$s"; then echo "  可开未开: CONFIG_$s"
  else echo "  本树没有: CONFIG_$s"; fi
done

echo "--- kernelrelease ---"
[ -f out/include/config/kernel.release ] && cat out/include/config/kernel.release
if [ "$fail" = 0 ]; then
  echo "CONFIG CHECK OK"
  echo "--- 编译为模块的符号（这些 .ko 必须与内核一起安装）---"
  grep '=m$' "$CFG" | sort || true
else
  echo "CONFIG CHECK FAILED"
fi
exit $fail
