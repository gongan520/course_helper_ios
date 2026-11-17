"""把静态「小新牵小白」素材注入 Widget 源码模板，生成可编译的 SignInActivityWidget.swift。

只有一张图：灵动岛改为「左边静态场景 + 右边跳动红心」，不需要逐帧素材。
base64 按 1200 字符分段拼成数组再 joined()：
单个 15KB 的字符串字面量会让 Swift 类型检查明显变慢，分段是常见做法。
"""
import base64
import os

TPL = "ios/SignInActivity/WidgetTemplate.swift.txt"
OUT = "ios/SignInActivity/SignInActivityWidget.swift"
PNG = "generated-images/out/scene_static.png"
CHUNK = 1200


def main():
    with open(PNG, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")

    parts = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
    body = "\n".join(f'        "{p}",' for p in parts)
    block = "[\n" + body + "\n    ].joined()"

    with open(TPL, "r", encoding="utf-8") as f:
        tpl = f.read()

    key = '"__SCENE__"'
    assert key in tpl, "模板里找不到 __SCENE__ 占位符"
    tpl = tpl.replace(key, block)

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(tpl)

    print(f"生成 {OUT} {os.path.getsize(OUT) / 1024:.1f}KB")
    print(f"素材 {len(b64) / 1024:.1f}KB base64，分 {len(parts)} 段")
    left = tpl.count("__")
    print("剩余占位符:", left)
    assert left == 0, "还有未替换的占位符"

    # 自检：数组元素必须都以 " 结尾并带逗号（上一版就是漏了逗号导致编译失败）
    bad = [i for i, l in enumerate(tpl.splitlines(), 1)
           if l.strip().startswith('"') and not l.strip().endswith('",')]
    print("缺逗号的字符串行:", bad[:5] if bad else "无")
    assert not bad, "base64 数组元素缺逗号"

    # 括号平衡自检（跳过 base64 行）
    lines = [l for l in tpl.splitlines() if not (l.strip().startswith('"') and len(l.strip()) > 200)]
    code = "\n".join(lines)
    for o, c in [("{", "}"), ("(", ")"), ("[", "]")]:
        assert code.count(o) == code.count(c), f"{o}{c} 不平衡"
    print("括号平衡: OK")


if __name__ == "__main__":
    main()
