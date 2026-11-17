"""从动画原画面生成「迈步」姿态帧。

思路：
- 单张静态图做整体平移 = 滑动，不像走路
- 走动感来自「腿绕髋关节摆动」：脚沿弧线抬起再落地，这是走路与滑动的本质区别
- 旋转作用窗口严格限定在腿所在矩形内（排除蓝色提包、黄色短裤），
  旋转中心放在短裤下摆上，使过渡处无缝
"""
import math
import os
from PIL import Image
import numpy as np

SRC = "generated-images/cut/scene_full.png"
OUT_DIR = "generated-images/walk"
FRAMES = 8

os.makedirs(OUT_DIR, exist_ok=True)


def bleed_colors(img, rounds=3):
    """清理透明区的 RGB，避免旋转插值时把残留底色混进边缘。

    抠图后透明区仍残留草地绿 / 被扩散成邻色（alpha=0 但 RGB 有值）。PIL 旋转用
    双三次插值且不预乘 alpha，会把这些 RGB 混成绿块、白块。这里直接把透明区
    RGB 置零，旋转边缘只出现半透明黑边 —— 与角色自带的黑描边一致，看不出来。
    """
    a = np.array(img)
    a[a[:, :, 3] == 0] = (0, 0, 0, 0)
    return Image.fromarray(a, "RGBA")


def rotate_leg(img, box, center, angle, feather_top=0, root_restore=0):
    """把 box 区域内绕 center 旋转 angle 度后贴回。

    box 必须只包含腿与鞋（不含提包、短裤），否则会把这些部件一起转歪。
    center 放在身体下沿处，使旋转中心附近几乎不动，与身体无缝衔接。
    root_restore：旋转后用原图覆盖顶部若干行，保证腿根始终与身体连着，
    不会因腿转走而在身体上留下矩形缺口（旋转中心就在这层，位移极小，接缝看不出）。
    """
    x0, y0, x1, y1 = box
    sub = img.crop(box)
    cx, cy = center[0] - x0, center[1] - y0
    rot = sub.rotate(angle, resample=Image.BICUBIC, center=(cx, cy),
                     fillcolor=(0, 0, 0, 0))

    if feather_top > 0:
        a = np.array(rot)
        h = a.shape[0]
        for y in range(min(feather_top, h)):
            w = (y + 1) / (feather_top + 1)
            a[y, :, 3] = (a[y, :, 3] * w).astype(np.uint8)
        rot = Image.fromarray(a, "RGBA")

    out = img.copy()
    # 清空 box（腿会移走，原处应露出背景），再叠上旋转后的腿
    out.paste(Image.new("RGBA", sub.size, (0, 0, 0, 0)), (x0, y0))
    out.alpha_composite(rot, (x0, y0))

    if root_restore > 0:
        out.paste(img.crop((x0, y0, x1, y0 + root_restore)), (x0, y0))
    return out


def build(frame_idx):
    img = bleed_colors(Image.open(SRC).convert("RGBA"))
    phase = frame_idx / FRAMES * 2 * math.pi
    s = math.sin(phase)
    c = math.cos(phase)

    # 小新前腿（伸出短裤右下，带黄鞋）：绕短裤下摆摆动 ±20°，
    # 摆幅刻意夸张 —— 缩小到灵动岛尺寸后，小幅摆动根本看不出在走
    img = rotate_leg(img, (156, 490, 292, 589), (196, 494),
                     angle=20 * s, feather_top=6, root_restore=8)

    # 小白：后腿与前腿反相摆动，形成交替迈步
    img = rotate_leg(img, (612, 523, 686, 589), (642, 527),
                     angle=-18 * s, feather_top=5, root_restore=8)
    img = rotate_leg(img, (756, 523, 834, 589), (788, 527),
                     angle=18 * s, feather_top=5, root_restore=8)

    # 尾巴跟着节奏左右摇，让整只狗显得有生气
    img = rotate_leg(img, (600, 352, 686, 442), (652, 438),
                     angle=13 * c, feather_top=0, root_restore=6)

    return img


def main():
    frames = [build(i) for i in range(FRAMES)]
    print("frames ok:", len(frames))

    # 预览：黑底横排
    pad = 8
    fw, fh = frames[0].size
    sheet = Image.new("RGBA", (fw * FRAMES + pad * (FRAMES + 1), fh + pad * 2), (18, 18, 18, 255))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (pad + i * (fw + pad), pad))
    sheet.convert("RGB").resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS).save(
        f"{OUT_DIR}/preview_sheet.png"
    )

    # 腿部局部对比（前 4 帧）
    crop_boxes = [(140, 450, 330, 589), (600, 480, 870, 589)]
    for idx, cb in enumerate(crop_boxes):
        crops = [f.crop(cb) for f in frames[:4]]
        w, h = crops[0].size
        strip = Image.new("RGB", (w * 4 + 10 * 5, h + 20), (10, 10, 10))
        for i, c in enumerate(crops):
            strip.paste(c.convert("RGB"), (10 + i * (w + 10), 10))
        strip = strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST)
        strip.save(f"{OUT_DIR}/check_{idx}.png")
        print("check", idx, strip.size)

    # 导出：缩到高 132px，量化压缩
    target_h = 132
    for i, f in enumerate(frames):
        w = round(f.width * target_h / f.height)
        small = f.resize((w, target_h), Image.LANCZOS)
        q = small.quantize(colors=96, method=Image.FASTOCTREE, dither=Image.NONE)
        q.save(f"{OUT_DIR}/walk{i}.png", optimize=True)
        print(f"walk{i}.png {small.size}", round(os.path.getsize(f'{OUT_DIR}/walk{i}.png') / 1024, 1), "KB")


if __name__ == "__main__":
    main()
