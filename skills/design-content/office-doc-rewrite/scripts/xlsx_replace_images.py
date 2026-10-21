# -*- coding: utf-8 -*-
"""
替换 xlsx 里的 xl/media/imageN.png,可选从原始文件恢复 drawing 锚点(修复之前改坏的框)。
用法:
  $OFFICE_PY xlsx_replace_images.py <in.xlsx> <out.xlsx> <img_map.json> [--restore-anchors-from <orig.xlsx>]
img_map.json: {"image1.png": "/path/new1.png", "image6.png": "/path/new6.png"}
--restore-anchors-from: 从该文件复制 xl/drawings/*.xml(把被改坏的锚点恢复成原样)
"""
import sys, json, zipfile, os

def main():
    in_x, out_x, map_f = sys.argv[1], sys.argv[2], sys.argv[3]
    img_map = json.load(open(map_f, encoding='utf-8'))
    restore = None
    if '--restore-anchors-from' in sys.argv:
        restore = sys.argv[sys.argv.index('--restore-anchors-from') + 1]

    z = zipfile.ZipFile(in_x)
    names = z.namelist()
    files = {n: z.read(n) for n in names}

    # 恢复 drawing 锚点
    if restore:
        rz = zipfile.ZipFile(restore)
        for n in rz.namelist():
            if n.startswith('xl/drawings/') and n.endswith('.xml') and n in files:
                files[n] = rz.read(n)
                print(f"恢复锚点 {n}")

    # 替换图片
    for img_name, new_path in img_map.items():
        key = f"xl/media/{img_name}"
        if key in files:
            files[key] = open(new_path, 'rb').read()
            print(f"替换 {img_name} ({os.path.getsize(new_path)//1024}KB)")
        else:
            print(f"⚠ {key} 不存在")

    if os.path.exists(out_x):
        os.remove(out_x)
    with zipfile.ZipFile(out_x, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in names:
            zo.writestr(n, files[n])
    print(f"已生成 {out_x}")

if __name__ == '__main__':
    main()
