# Regenerate slides/assets/qr.svg (needs: pip install qrcode):
#   python3 slides/assets/qr.py https://github.com/cp-20/regex-calc > slides/assets/qr.svg
# ECC H, dot modules, GitHub mark in a centre hole small enough to still decode
# (verified with zxing-cpp / OpenCV on the rendered slide).
import qrcode, sys
q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_H, border=0)
q.add_data(sys.argv[1]); q.make(fit=True)
m = q.get_matrix(); n = len(m)
# hole for a centre logo (about 22% of the width)
c = n / 2; hole = n * 0.16
def in_finder(x, y): return (x < 7 and y < 7) or (x >= n-7 and y < 7) or (x < 7 and y >= n-7)
def in_hole(x, y): return abs(x + .5 - c) < hole and abs(y + .5 - c) < hole
out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 {n+2} {n+2}" fill="currentColor">']
for y in range(n):
    for x in range(n):
        if m[y][x] and not in_finder(x, y) and not in_hole(x, y):
            out.append(f'<circle cx="{x+.5}" cy="{y+.5}" r=".47"/>')
for fx, fy in ((0, 0), (n-7, 0), (0, n-7)):
    out.append(f'<rect x="{fx+.5}" y="{fy+.5}" width="6" height="6" rx="1.3" fill="none" stroke="currentColor" stroke-width="1"/>')
    out.append(f'<rect x="{fx+2}" y="{fy+2}" width="3" height="3" rx=".6"/>')
# GitHub mark (Octicons mark-github, 16x16) in the hole
s = hole * 1.7 / 16
out.append(f'<g transform="translate({c-8*s} {c-8*s}) scale({s})"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></g>')
out.append('</svg>')
print(''.join(out))
