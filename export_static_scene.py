"""导出一张静态「小新牵小白」场景图（含 base64）。

不再需要逐帧动画素材：灵动岛改为静态场景 + 右侧跳动红心。
"""
import base64
import os

from PIL import Image
import numpy as np

SRC = "generated-images/cut/scene_full.png"
OUT_DIR = "generated-images/out"
TARGET_H = 264          # 锁屏卡片最高约 46pt，@3x = 138px，留 2 倍余量

os.makedirs(OUT_DIR, exist_ok=True)

im = Image.open(SRC).convert("RGBA")
a = np.array(im)
ys, xs = np.where(a[:, :, 3] > 8)
box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
im = im.crop(box)
print("裁切后", im.size)

w = round(im.width * TARGET_H / im.height)
im = im.resize((w, TARGET_H), Image.LANCZOS)

# 量化压缩：卡通平涂色，160 色足够，体积能降到 1/4
# RGBA 只能用 FASTOCTREE 量化（MEDIANCUT 不支持带 alpha）
q = im.quantize(colors=160, method=Image.FASTOCTREE, dither=Image.NONE)
q.save(os.path.join(OUT_DIR, "scene_static.png"), optimize=True)

raw = open(os.path.join(OUT_DIR, "scene_static.png"), "rb").read()
b64 = base64.b64encode(raw).decode("ascii")
open(os.path.join(OUT_DIR, "scene_static.b64"), "w").write(b64)

print("输出尺寸", im.size, "宽高比 %.4f" % (im.width / im.height))
print("PNG", round(len(raw) / 1024, 1), "KB  base64", round(len(b64) / 1024, 1), "KB")
