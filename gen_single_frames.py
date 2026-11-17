"""生成单角色（小新 / 小白）的 8 帧迈步姿态。

紧凑态的可用宽度只有十几 pt，放进整幅场景（小新+狗+绳）后每个角色只剩几像素，
腿的摆动根本看不出来。所以紧凑态改成单人独立显示，尺寸能放满胶囊高度。
"""
import os

import numpy as np
from PIL import Image

from gen_walk_frames import FRAMES, build


def bbox_of(im, thresh=20):
    a = np.array(im)[:, :, 3]
    ys, xs = np.where(a > thresh)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def export(name, crop_box, target_h, pad=3):
    """按固定裁剪框导出 8 帧。

    裁剪框必须固定（取第 0 帧的包围盒），不能逐帧求 bbox —— 腿摆动会改变包围盒，
    导致每帧尺寸不同，播放时角色会抖动。
    """
    out_dir = "generated-images/single"
    os.makedirs(out_dir, exist_ok=True)

    raws = []
    for i in range(FRAMES):
        full = build(i)
        raws.append(full.crop(crop_box))

    x0, y0, x1, y1 = bbox_of(raws[0])
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(raws[0].width, x1 + pad)
    y1 = min(raws[0].height, y1 + pad)
    fixed = (x0, y0, x1, y1)
    print(f"{name} 固定裁剪框 {fixed} 尺寸 {(x1 - x0, y1 - y0)}")

    w = round((x1 - x0) * target_h / (y1 - y0))
    for i, im in enumerate(raws):
        piece = im.crop(fixed).resize((w, target_h), Image.LANCZOS)
        q = piece.quantize(colors=80, method=Image.FASTOCTREE, dither=Image.NONE)
        q.save(f"{out_dir}/{name}{i}.png", optimize=True)

    sizes = [os.path.getsize(f"{out_dir}/{name}{i}.png") for i in range(FRAMES)]
    print(f"  导出 {w}x{target_h} 共 {FRAMES} 帧，平均 {sum(sizes)/len(sizes)/1024:.1f}KB")
    return w, target_h


def preview(name, total_h=52):
    frames = [Image.open(f"generated-images/single/{name}{i}.png").convert("RGBA")
              for i in range(FRAMES)]
    scaled = []
    for f in frames:
        w = round(f.width * total_h / f.height)
        scaled.append(f.resize((w, total_h), Image.LANCZOS))
    w, h = scaled[0].size
    sheet = Image.new("RGB", (w * FRAMES + 6 * (FRAMES + 1), h + 12), (0, 0, 0))
    for i, f in enumerate(scaled):
        tmp = Image.new("RGBA", f.size, (0, 0, 0, 255))
        tmp.alpha_composite(f)
        sheet.paste(tmp.convert("RGB"), (6 + i * (w + 6), 6))
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.LANCZOS)
    sheet.save(f"generated-images/single/preview_{name}.png")
    print(f"  预览 preview_{name}.png {sheet.size}")


if __name__ == "__main__":
    # 小新：左侧主体，含伸出的右臂与一截狗绳
    export("shin", (0, 0, 392, 589), 132)
    # 小白：右侧主体
    export("dog", (505, 320, 915, 589), 96)
    preview("shin")
    preview("dog")
