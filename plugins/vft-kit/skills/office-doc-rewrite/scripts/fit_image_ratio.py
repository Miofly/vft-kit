# -*- coding: utf-8 -*-
"""
把图片 padding 加白边到目标长宽比(绝不拉伸/裁剪),使其精确填充 xlsx 的图框而不变形。
用法:
  $OFFICE_PY fit_image_ratio.py <in.png> <out.png> <target_ratio>
  target_ratio = 框的 宽/高(用 xlsx_measure_frames.py 量得)
批量:
  $OFFICE_PY fit_image_ratio.py --batch <spec.json>
  spec.json: {"/path/img1.png": {"out": "/path/o1.png", "ratio": 2.14}, ...}
"""
import sys, json
from PIL import Image

def pad(in_p, out_p, target, bg="white"):
    im = Image.open(in_p).convert("RGB")
    w, h = im.size
    cur = w / h
    if abs(cur - target) < 0.02:
        out = im
    elif cur < target:          # 太窄 → 左右加白边
        nw = int(round(h * target))
        out = Image.new("RGB", (nw, h), bg)
        out.paste(im, ((nw - w) // 2, 0))
    else:                       # 太宽 → 上下加白边
        nh = int(round(w / target))
        out = Image.new("RGB", (w, nh), bg)
        out.paste(im, (0, (nh - h) // 2))
    out.save(out_p)
    return out.size

def main():
    if sys.argv[1] == '--batch':
        spec = json.load(open(sys.argv[2], encoding='utf-8'))
        for src, cfg in spec.items():
            sz = pad(src, cfg['out'], float(cfg['ratio']))
            print(f"{src} -> {cfg['out']} {sz} (比{cfg['ratio']})")
    else:
        in_p, out_p, ratio = sys.argv[1], sys.argv[2], float(sys.argv[3])
        sz = pad(in_p, out_p, ratio)
        print(f"padding 到 {sz} (比{ratio})")

if __name__ == '__main__':
    main()
