"""把 8 帧迈步素材注入 Widget 源码模板，生成可编译的 SignInActivityWidget.swift。"""
import base64
import os

TPL = "ios/SignInActivity/WidgetTemplate.swift.txt"
OUT = "ios/SignInActivity/SignInActivityWidget.swift"
FRAMES = 8


def b64_png(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def b64_text(path):
    with open(path, "r", encoding="ascii") as f:
        return f.read().strip()


def main():
    with open(TPL, "r", encoding="utf-8") as f:
        tpl = f.read()

    # 8 帧走路姿态
    for i in range(FRAMES):
        path = f"generated-images/walk/walk{i}.png"
        assert os.path.exists(path), path
        tpl = tpl.replace(f'"__WALK{i}__"', '"' + b64_png(path) + '"')

    # 极简态单角色
    tpl = tpl.replace('"__SHIN_B64__"', '"' + b64_text("generated-images/out/shin.b64") + '"')
    tpl = tpl.replace('"__DOG_B64__"', '"' + b64_text("generated-images/out/dog.b64") + '"')

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(tpl)

    left = tpl.count("__")
    print("生成", OUT, round(os.path.getsize(OUT) / 1024, 1), "KB")
    print("剩余占位符:", left)
    assert left == 0, "还有未替换的占位符"

    # 自检：数组元素必须都以 " 结尾并带逗号
    bad = []
    for idx, line in enumerate(tpl.splitlines(), 1):
        s = line.strip()
        if s.startswith('"') and not s.endswith('",'):
            bad.append(idx)
    print("缺逗号的字符串行:", bad[:5] if bad else "无")


if __name__ == "__main__":
    main()
