#!/usr/bin/env python3
"""把 xt_qtaguid 的接口统计改成恒为 0（hengwu0 docker 补丁的等价实现）。

原因：容器会不断创建/销毁 netns 与网络接口，3.18 的 xt_qtaguid 在 iface_entry->active
时直接 dev_get_stats(iface_entry->net_dev)，这条路径在 r9s 上会踩到已注销的设备。
代价：Android 的流量统计（设置里的数据使用量、TrafficStats）不再准确。

只改 iface_stat_fmt_proc_show 这一个函数（文件里有三处相同的变量声明，
盲目全文替换会破坏其它函数），匹配不到就报错退出，绝不静默跳过。
"""
import re
import sys

PATH = "net/netfilter/xt_qtaguid.c"

FUNC = re.compile(
    r"static int iface_stat_fmt_proc_show\(struct seq_file \*m, void \*v\)\n\{.*?\n\}\n",
    re.S,
)
BLOCK = re.compile(
    r"[ \t]*if \(iface_entry->active\) \{\n"
    r"[ \t]*stats = dev_get_stats\(iface_entry->net_dev,\n"
    r"[ \t]*&dev_stats\);\n"
    r"[ \t]*\} else \{\n"
    r"[ \t]*stats = &no_dev_stats;\n"
    r"[ \t]*\}\n",
    re.M,
)
DECL = re.compile(r"struct rtnl_link_stats64 dev_stats, \*stats;")

with open(PATH, encoding="latin-1", newline="") as f:
    text = f.read()

funcs = FUNC.findall(text)
if len(funcs) != 1:
    sys.exit("FAIL: expected 1 definition of iface_stat_fmt_proc_show, found %d" % len(funcs))
body = funcs[0]
if "/* containers: never touch net_dev */" in body:
    print("already patched")
    sys.exit(0)
if len(BLOCK.findall(body)) != 1 or len(DECL.findall(body)) != 1:
    sys.exit("FAIL: pattern not found inside the function (kernel source differs?)")

new_body = DECL.sub("struct rtnl_link_stats64 *stats;", body)
new_body = BLOCK.sub("\tstats = &no_dev_stats;  /* containers: never touch net_dev */\n", new_body)
# 去掉现在没用到的 dev_stats 变量后，no_dev_stats 仍被使用，编译干净

text = text.replace(body, new_body)
with open(PATH, "w", encoding="latin-1", newline="") as f:
    f.write(text)
print("patched %s" % PATH)
