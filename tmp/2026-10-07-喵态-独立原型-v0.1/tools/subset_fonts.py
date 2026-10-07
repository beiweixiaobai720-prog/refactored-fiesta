#!/usr/bin/env python3
"""把游戏里用到的每一个字（脚本 + 关卡数据）收集起来，裁剪两套 OFL 字体。

用法：python3 tools/subset_fonts.py <LXGWWenKai-Regular.ttf> <ZCOOLKuaiLe-Regular.ttf>
改过任何界面文字或关卡提示之后都要重跑一次，否则新字会显示成方块。
需要 fonttools（pip install fonttools）。
"""
import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot")
EXTRA = "，。：；！？、“”‘’（）《》·—…★☆♪×＋－「」『』【】～％／←→↑↓✓"


def main() -> None:
    wenkai_src, kuaile_src = sys.argv[1], sys.argv[2]
    chars = set()
    sources = glob.glob(os.path.join(ROOT, "scripts", "*.gd")) + glob.glob(os.path.join(ROOT, "levels", "*.json"))
    for path in sources:
        with open(path, encoding="utf-8") as f:
            chars.update(f.read())
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update(EXTRA)
    text = "".join(sorted(c for c in chars if c.isprintable()))
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False) as tf:
        tf.write(text)
        chars_path = tf.name
    try:
        for src, dst in [(wenkai_src, "wenkai.ttf"), (kuaile_src, "kuaile.ttf")]:
            out = os.path.join(ROOT, "fonts", dst)
            subprocess.check_call(["pyftsubset", src, "--text-file=" + chars_path, "--output-file=" + out,
                                   "--layout-features=*", "--no-hinting"])
            print(dst, os.path.getsize(out), "bytes")
    finally:
        os.unlink(chars_path)
    print(len(text), "chars from", len(sources), "files")


if __name__ == "__main__":
    main()
