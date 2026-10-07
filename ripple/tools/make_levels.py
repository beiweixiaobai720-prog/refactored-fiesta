#!/usr/bin/env python3
"""关卡生成器：用矩形等图元画出 64x36 的字符地图，输出 scripts/levels.gd。

用法：python3 tools/make_levels.py
地图字符见 scripts/level.gd 顶部注释。也可以直接手改 levels.gd 里的字符画。
"""
from pathlib import Path

W, H = 64, 36


class Map:
    def __init__(self):
        self.g = [["." for _ in range(W)] for _ in range(H)]

    def rect(self, x0, y0, x1, y1, ch):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                self.g[y][x] = ch
        return self

    def put(self, x, y, ch):
        self.g[y][x] = ch
        return self

    def path(self, pts, ch, width=1):
        """沿折线铺一条宽 width 的通道（pts 只能水平/竖直相连）。"""
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            x0, x1 = sorted((ax, bx))
            y0, y1 = sorted((ay, by))
            self.rect(x0, y0, x1 + width - 1, y1 + width - 1, ch)
        return self

    def rows(self):
        return ["".join(r) for r in self.g]


LEVELS = []


def level(name, poem, keys="", pacers=None):
    def deco(fn):
        m = Map()
        fn(m)
        LEVELS.append({"name": name, "poem": poem, "keys": keys, "pacers": pacers or [], "map": m.rows()})
        return fn
    return deco


KEYS = "← →  移动      空格  跳      J / ↓  踩      R  重来      Esc  标题"


# 01 初涟：踩一下，骑着自己的波上去。
@level("初涟", "跳进去，踩一下。", KEYS)
def _(m):
    m.rect(0, 31, 63, 35, "#")
    m.rect(0, 21, 14, 35, "#")           # 出生台
    m.rect(15, 12, 23, 30, "~")          # 活膜池
    m.rect(24, 12, 63, 35, "#")          # 高台
    m.put(6, 20, "P")
    m.put(44, 11, "E")


# 02 接力：在波顶起跳；波会沿着通道去到别的池子。
@level("接力", "波顶起跳，跳得更高。", KEYS)
def _(m):
    m.rect(0, 24, 11, 35, "#")           # 出生台
    m.rect(12, 19, 23, 30, "~")          # 池 A
    m.rect(12, 31, 23, 35, "#")
    m.rect(24, 15, 27, 35, "#")          # 墙 1（比池 A 顶高 4 格）
    m.rect(28, 8, 39, 21, "~")           # 池 B
    m.rect(28, 22, 39, 35, "#")
    m.rect(40, 6, 42, 35, "#")           # 隔墙
    m.path([(40, 21), (41, 21), (41, 29), (42, 29)], "~")   # 隔墙里的细通道：B -> C 底部（人钻不过去）
    m.rect(43, 8, 52, 30, "~")           # 池 C（底是刺，不能踩）
    m.rect(43, 31, 52, 31, "^")
    m.rect(43, 32, 52, 35, "#")
    m.rect(53, 6, 63, 35, "#")           # 终点台
    m.put(5, 23, "P")
    m.put(59, 5, "E")


# 03 穿隙：波能穿过你过不去的缝，替你去敲钟。
@level("穿隙", "涟漪会去你去不了的地方。", KEYS)
def _(m):
    m.rect(0, 31, 63, 35, "#")
    m.rect(0, 18, 3, 35, "#")
    m.rect(4, 14, 25, 30, "~")           # 主池
    m.rect(26, 14, 63, 35, "#")          # 实心台，里面掏出迷宫
    m.put(26, 28, "~")                   # 1 格的缝
    m.path([(27, 27), (33, 27), (33, 17), (44, 17), (44, 28), (51, 28), (51, 21), (53, 21)], "~", 2)
    m.put(54, 21, "B").put(54, 22, "~")
    m.rect(40, 4, 41, 9, "#")            # 门上方的墙
    m.rect(40, 10, 41, 13, "G")          # 门
    m.rect(26, 4, 63, 4, "#")            # 天花板
    m.put(1, 17, "P")
    m.put(58, 13, "E")


# 04 相消：两道波相撞会互相抵消。敌人的波也能当电梯。
@level("相消", "以浪止浪。", KEYS, pacers=[{"period": 3.0, "first": 1.4}])
def _(m):
    m.rect(0, 29, 63, 35, "#")           # 地面
    m.rect(0, 20, 56, 23, "#")           # 走廊天花板
    m.rect(0, 24, 0, 28, "#")
    m.rect(1, 24, 56, 28, "~")           # 走廊
    m.rect(1, 28, 3, 28, "^")            # 左端地刺
    m.rect(1, 24, 1, 27, "#")
    m.rect(46, 6, 56, 19, "#")           # 终点塔
    m.rect(57, 6, 61, 28, "~")           # 竖井
    m.rect(62, 0, 63, 35, "#")
    m.put(59, 28, "*")                   # 起搏器
    m.put(8, 28, "p")
    m.put(50, 5, "E")


# 05 抢拍：上方的起搏器不停往下发波，倦了的膜踩不亮。抢在两拍之间。
@level("抢拍", "倦了的地方，踩不亮。", "", pacers=[{"period": 3.4, "first": 0.0}])
def _(m):
    m.rect(0, 0, 21, 35, "#")
    m.rect(42, 0, 63, 35, "#")
    m.rect(22, 3, 41, 30, "~")           # 竖井
    m.rect(22, 31, 41, 31, "^")
    m.rect(22, 32, 41, 35, "#")
    m.rect(22, 29, 28, 30, "#")          # L0（出发）
    m.rect(35, 24, 41, 24, "#")          # L1
    m.rect(22, 19, 28, 19, "#")          # L2
    m.rect(35, 14, 41, 14, "#")          # L3
    m.rect(22, 9, 28, 9, "#")            # L4
    m.rect(35, 5, 41, 5, "#")            # L5，连着出口通道
    m.rect(42, 2, 63, 4, ".")            # 右上出口通道
    m.put(31, 3, "*")
    m.put(25, 28, "p")
    m.put(59, 4, "E")


# 06 迟到的浪：一次踩，三座电梯，按路程先后到达。
@level("迟到的浪", "路有多长，它就迟多久。")
def _(m):
    m.rect(0, 30, 63, 35, "#")
    m.rect(1, 12, 8, 29, "~")            # 起步池
    m.rect(9, 12, 11, 29, "#")           # 柱 1
    m.rect(12, 10, 20, 28, "~")          # 池 1（底是刺；宽到跳不过去）
    m.rect(12, 29, 20, 29, "^")
    m.rect(21, 12, 25, 29, "#")          # 柱 2
    m.rect(26, 10, 34, 28, "~")          # 池 2
    m.rect(26, 29, 34, 29, "^")
    m.rect(35, 12, 39, 29, "#")          # 柱 3
    m.rect(40, 10, 48, 28, "~")          # 池 3
    m.rect(40, 29, 48, 29, "^")
    m.rect(49, 12, 63, 29, "#")          # 终点台
    # 地下通道：起步池底 -> 各池侧下方的小孔
    m.path([(4, 30), (4, 32), (36, 32)], "~", 1)
    m.path([(10, 32), (10, 27), (11, 27)], "~", 1)                         # -> 池 1（直达）
    m.path([(22, 32), (22, 14), (24, 14), (24, 27), (25, 27)], "~", 1)     # -> 池 2：在柱子里绕一大圈
    m.path([(36, 32), (36, 14), (38, 14), (38, 27), (39, 27)], "~", 1)     # -> 池 3：同样绕一圈
    m.put(3, 29, "p")
    m.put(57, 11, "E")


# 07 回环：钟响开坝。只有一个方向的波，才能一直转下去。
@level("回环", "先到的，决定方向。")
def _(m):
    m.rect(0, 0, 63, 35, "#")
    m.rect(0, 0, 63, 7, ".")             # 上方空气
    m.rect(0, 8, 9, 35, "#")             # 出生台
    m.rect(10, 8, 11, 15, "~")           # 下降井（也是电梯）
    m.rect(10, 16, 31, 29, "~")          # 回环外框
    m.rect(12, 18, 29, 27, "#")          # 中间的岛
    m.put(15, 16, "B").put(15, 17, "~")  # 钟：靠近入口
    m.rect(30, 24, 31, 24, "D")          # 坝：在右侧，离入口远
    m.path([(32, 20), (39, 20)], "~", 1)  # 漏向竖井的细缝
    m.rect(40, 4, 46, 29, "~")           # 竖井（底是刺）
    m.rect(40, 30, 46, 30, "^")
    m.rect(47, 0, 63, 35, "#")
    m.rect(47, 0, 63, 3, ".")
    m.rect(12, 8, 39, 15, "#")
    m.rect(32, 4, 39, 7, ".")
    m.put(4, 7, "P")
    m.put(58, 3, "E")


# 08 旋：断开的波会卷成永不停歇的螺旋，它替你一遍遍推起远处的电梯。
@level("旋", "它会自己转下去。")
def _(m):
    m.rect(0, 0, 63, 35, "#")
    m.rect(0, 0, 63, 5, ".")             # 顶部敞开
    m.rect(0, 6, 6, 11, ".")             # 出生台上方
    m.rect(7, 6, 25, 11, ".")
    m.rect(7, 12, 25, 30, "~")           # 旋室：一大片活膜
    m.rect(14, 19, 18, 22, "#")          # 岛
    m.rect(16, 23, 17, 30, "D")          # 坝：岛到地面
    m.put(16, 13, "B")
    m.rect(26, 6, 28, 11, ".")           # 柱 1（顶在第 12 行）
    m.rect(29, 6, 36, 15, ".")
    m.rect(29, 16, 36, 30, "~")          # 池 A（底是刺）
    m.rect(29, 31, 36, 31, "^")
    m.path([(26, 29), (28, 29)], "~")    # 旋室 -> 池 A 底部的细缝
    m.rect(37, 6, 40, 10, ".")           # 柱 2（顶在第 11 行）
    m.rect(41, 6, 48, 8, ".")
    m.rect(41, 9, 48, 30, "~")           # 池 B（底是刺）
    m.rect(41, 31, 48, 31, "^")
    m.path([(23, 31), (23, 33), (38, 33), (38, 29), (40, 29)], "~")   # 旋室 -> 池 B：地下通道
    m.rect(49, 6, 63, 6, ".")            # 终点台（顶在第 7 行）
    m.put(3, 11, "P")
    m.put(58, 6, "E")


# 09 心跳：最后一关。一颗停跳的心：在对的地方踩下去，让它重新跳起来——它会一下一下把你送上去。
@level("心跳", "让它重新跳起来。")
def _(m):
    m.rect(0, 0, 63, 35, "#")
    m.rect(0, 0, 45, 13, ".")            # 上方空气，第 14 行是走道
    cx, cy, sx, sy = 25.5, 25.2, 17.0, 8.6
    for y in range(15, H):
        for x in range(W):
            u = (x + 0.5 - cx) / sx
            v = -(y + 0.5 - cy) / sy
            if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0:
                m.put(x, y, "~")
    m.rect(22, 24, 29, 27, "#")          # 心核（岛）
    for y in range(28, H):               # 坝：心核到心尖
        for x in (25, 26):
            if m.g[y][x] == "~":
                m.put(x, y, "D")
    m.rect(11, 14, 12, 16, ".")          # 左心房顶上的落口
    m.put(13, 17, "B")                   # 钟：就在落口旁边
    m.rect(24, 14, 27, 17, "~")          # 心口：向上通到走道的颈
    m.put(3, 13, "P")
    # 右边：一条底是刺的长血管，只有心跳能把人一次次送上去
    m.rect(46, 0, 48, 31, ".")           # 走道尽头的深渊
    m.rect(46, 32, 48, 32, "^")
    m.rect(49, 2, 55, 31, "~")           # 血管
    m.rect(49, 32, 55, 32, "^")
    m.path([(36, 29), (37, 29), (37, 34), (57, 34), (57, 30), (56, 30)], "~")   # 心底右侧 -> 血管右下的细通道
    m.rect(49, 0, 63, 1, ".")            # 血管顶上和终点台上方留出空间
    m.put(60, 1, "E")


def emit():
    out = ["class_name Levels", "extends RefCounted", "## 由 tools/make_levels.py 生成；也可直接手改字符画。", "", "", "static func all() -> Array:", "\treturn ["]
    for L in LEVELS:
        out.append("\t\t{")
        out.append(f'\t\t\t"name": "{L["name"]}",')
        out.append(f'\t\t\t"poem": "{L["poem"]}",')
        out.append(f'\t\t\t"keys": "{L["keys"]}",')
        pcs = ", ".join("{" + f'"period": {p["period"]}, "first": {p["first"]}' + "}" for p in L["pacers"])
        out.append(f'\t\t\t"pacers": [{pcs}],')
        out.append('\t\t\t"map": [')
        for r in L["map"]:
            out.append(f'\t\t\t\t"{r}",')
        out.append("\t\t\t],")
        out.append("\t\t},")
    out.append("\t]")
    p = Path(__file__).resolve().parent.parent / "scripts" / "levels.gd"
    p.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("wrote", p, len(LEVELS), "levels")


if __name__ == "__main__":
    emit()
