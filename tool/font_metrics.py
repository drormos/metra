#!/usr/bin/env python3
"""Print a TrueType font's vertical metrics (no dependencies).

Usage: python3 tool/font_metrics.py assets/fonts/SairaExtraCondensed-Bold.ttf

Flutter lays text out with these (hhea, or OS/2 typo metrics when the font
asks for them): with `height: 1` and proportional leading the baseline sits
at ascent / (ascent + descent) of the line; with even leading the font's
box is centred. Cap height says where the top of capitals and digits is,
for optical centring (see the visual-check skill).
"""
import struct
import sys


def tables(data):
    count = struct.unpack('>H', data[4:6])[0]
    out = {}
    for i in range(count):
        tag, _, offset, _ = struct.unpack('>4sIII', data[12 + 16 * i:28 + 16 * i])
        out[tag.decode('latin-1')] = offset
    return out


def main(path):
    data = open(path, 'rb').read()
    t = tables(data)
    upem = struct.unpack('>H', data[t['head'] + 18:t['head'] + 20])[0]
    asc, desc, gap = struct.unpack('>hhh', data[t['hhea'] + 4:t['hhea'] + 10])
    os2 = t['OS/2']
    version = struct.unpack('>H', data[os2:os2 + 2])[0]
    selection = struct.unpack('>H', data[os2 + 62:os2 + 64])[0]
    t_asc, t_desc, t_gap, w_asc, w_desc = struct.unpack('>hhhHH', data[os2 + 68:os2 + 78])
    x_height = cap = None
    if version >= 2:
        x_height, cap = struct.unpack('>hh', data[os2 + 86:os2 + 90])
    print(f'{path}')
    print(f'  units per em   {upem}')
    print(f'  hhea           ascent {asc}  descent {desc}  line gap {gap}')
    print(f'  OS/2 typo      ascent {t_asc}  descent {t_desc}  line gap {t_gap}'
          f'  (use typo metrics: {bool(selection & 128)})')
    print(f'  OS/2 win       ascent {w_asc}  descent {w_desc}')
    print(f'  x-height {x_height}  cap height {cap}')
    if cap:
        a, d = asc / upem, -desc / upem
        c = cap / upem
        prop = a / (a + d) - c / 2  # digit centre in a height-1 line box
        even = (1 - (a + d)) / 2 + a - c / 2
        print(f'  height 1: digit centre at {prop:.3f} em (proportional),'
              f' {even:.3f} em (even); 0.5 is centred')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
