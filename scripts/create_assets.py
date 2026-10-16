"""Create a geometric app mark and labeled design illustration without external libraries."""
from pathlib import Path
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
catalog = ROOT / 'App' / 'Assets.xcassets'
icon_dir = catalog / 'AppIcon.appiconset'
icon_dir.mkdir(parents=True, exist_ok=True)
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(icon_dir / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

def png(size, path):
    pixels = bytearray([250, 238, 231] * size * size)
    # Heart outline sampled parametrically, filled by scanlines.
    polygon = []
    for i in range(721):
        t = i * math.pi / 360
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t)
        polygon.append((size * (.5 + x / 48), size * (.49 - y / 48)))
    for y in range(size):
        intersections = []
        for (x1,y1), (x2,y2) in zip(polygon, polygon[1:]):
            if min(y1,y2) <= y + .5 < max(y1,y2):
                intersections.append(x1 + (y + .5 - y1) * (x2-x1) / (y2-y1))
        intersections.sort()
        for a,b in zip(intersections[::2], intersections[1::2]):
            for x in range(max(0, math.ceil(a)), min(size, math.ceil(b))):
                offset = (y * size + x) * 3
                pixels[offset:offset+3] = bytes((171, 72, 96))
    # A rising rhythm line crossing the heart.
    points = [(.23,.53), (.37,.53), (.44,.43), (.51,.62), (.59,.48), (.66,.53), (.77,.53)]
    for (ax,ay),(bx,by) in zip(points,points[1:]):
        ax*=size; ay*=size; bx*=size; by*=size
        steps = int(max(abs(bx-ax),abs(by-ay)))+1
        radius = max(1, size // 95)
        for step in range(steps+1):
            cx = int(ax+(bx-ax)*step/steps); cy = int(ay+(by-ay)*step/steps)
            for dy in range(-radius,radius+1):
                for dx in range(-radius,radius+1):
                    x,y = cx+dx,cy+dy
                    if dx*dx+dy*dy <= radius*radius and 0 <= x < size and 0 <= y < size:
                        offset = (y*size+x)*3; pixels[offset:offset+3] = bytes((255,248,240))
    raw = b''.join(b'\x00' + pixels[y*size*3:(y+1)*size*3] for y in range(size))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b''))

png(1024, icon_dir / 'AppIcon.png')
docs = ROOT / 'docs' / 'images'
docs.mkdir(parents=True, exist_ok=True)
themes = [('Claro', '#f4f1eb', '#ffffff', '#263b30', '#526c5d'), ('Escuro', '#18211d', '#25332b', '#f4f0e7', '#9abb9e'), ('Rosa', '#fff0f3', '#fffafb', '#572c3b', '#b64b72')]
parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1260" height="840" viewBox="0 0 1260 840">', '<rect width="1260" height="840" fill="#e8e1d8"/>', '<text x="50" y="50" font-family="Arial" font-size="24" fill="#293c30">Nosso Ritmo · conceito visual dos três temas</text>']
for i,(label,bg,card,fg,accent) in enumerate(themes):
    x = 45+i*410
    parts.extend([f'<g transform="translate({x},85)">', f'<rect width="375" height="690" rx="38" fill="{bg}" stroke="{fg}" stroke-width="2"/>', f'<text x="26" y="42" font-family="Arial" font-size="14" fill="{accent}">9:41                         {label}</text>', f'<text x="26" y="95" font-family="Arial" font-size="17" fill="{accent}">NOSSO RITMO</text>', f'<text x="26" y="144" font-family="Georgia" font-size="29" fill="{fg}">A vida acontece</text>', f'<text x="26" y="182" font-family="Georgia" font-size="29" fill="{fg}">nos nossos encontros.</text>', f'<text x="26" y="217" font-family="Arial" font-size="15" fill="{accent}">Alex &amp; Dani</text>', f'<rect x="20" y="246" width="335" height="135" rx="24" fill="{card}"/>', f'<text x="38" y="276" font-family="Arial" font-size="13" fill="{accent}">NOSSO PRÓXIMO MOMENTO</text>', f'<text x="38" y="312" font-family="Georgia" font-size="23" fill="{fg}">Um café sem pressa</text>', f'<text x="38" y="344" font-family="Arial" font-size="14" fill="{fg}">Amanhã, 17:00 · A dois</text>', f'<text x="26" y="423" font-family="Arial" font-size="18" fill="{fg}">Uma semana no nosso ritmo</text>'])
    for j,(name,value,ratio) in enumerate([('Mais céu, mais nós','1,5 de 3 h ao ar livre',.5),('Nossa sessão de cinema','1 de 2 h de streaming',.5)]):
        y=446+j*94
        parts.extend([f'<rect x="20" y="{y}" width="335" height="82" rx="18" fill="{card}"/>', f'<text x="38" y="{y+24}" font-family="Arial" font-size="15" fill="{fg}">{name}</text>',f'<rect x="38" y="{y+37}" width="298" height="5" rx="2" fill="{bg}"/>',f'<rect x="38" y="{y+37}" width="149" height="5" rx="2" fill="{accent}"/>', f'<text x="38" y="{y+64}" font-family="Arial" font-size="12" fill="{accent}">{value}</text>'])
    parts.extend([f'<text x="28" y="665" font-family="Arial" font-size="13" fill="{fg}">Hoje      Agenda      Metas      Viagens      Nós</text>', '</g>'])
parts.extend(['<text x="50" y="817" font-family="Arial" font-size="14" fill="#48584c">Ilustração de referência — não é captura do app executando. Dados fictícios.</text>', '</svg>'])
(docs / 'themes.svg').write_text('\n'.join(parts) + '\n', encoding='utf-8')
print('Created opaque 1024px icon and labeled theme illustration.')
