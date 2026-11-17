"""把三套 8 帧迈步素材注入 Widget 源码模板，生成可编译的 SignInActivityWidget.swift。"""
import base64
import os

TPL = "ios/SignInActivity/WidgetTemplate.swift.txt"
OUT = "ios/SignInActivity/SignInActivityWidget.swift"
FRAMES = 8

# 占位符前缀 -> 素材文件模板
SETS = [
    ("WALK", "generated-images/walk/walk{}.png"),
    ("SHIN", "generated-images/single/shin{}.png"),
    ("DOG", "generated-images/single/dog{}.png"),
]


def b64_png(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def main():
    with open(TPL, "r", encoding="utf-8") as f:
        tpl = f.read()

    total = 0
    for prefix, pattern in SETS:
        for i in range(FRAMES):
            path = pattern.format(i)
            assert os.path.exists(path), path
            data = b64_png(path)
            total += len(data)
            key = f'"__{prefix}{i}__"'
            assert key in tpl, key
            tpl = tpl.replace(key, '"' + data + '"')

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(tpl)

    left = tpl.count("__")
    print(f"生成 {OUT} {os.path.getsize(OUT)/1024:.1f}KB  素材内嵌 {total/1024:.1f}KB")
    print("剩余占位符:", left)
    assert left == 0, "还有未替换的占位符"

    # 自检：数组元素必须都以 " 结尾并带逗号
    bad = [i for i, l in enumerate(tpl.splitlines(), 1)
           if l.strip().startswith('"') and not l.strip().endswith('",')]
    print("缺逗号的字符串行:", bad[:5] if bad else "无")


if __name__ == "__main__":
    main()
