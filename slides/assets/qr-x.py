# Regenerate slides/assets/qr-x.svg, the X profile QR (needs: pip install qrcode):
#   python3 slides/assets/qr-x.py https://x.com/__cp20__ > slides/assets/qr-x.svg
# ECC H, dot modules, round "eyes" (class="eye", coloured by the deck's CSS) and a round
# hole in the centre for the avatar, which the deck overlays as its own element so it can
# morph in from the title slide.  The hole radius is written to data-hole (fraction of the
# viewBox width) so the overlay can be sized to match.  Verified to decode with zxing-cpp
# on the rendered slides (intro size and the small corner size).
import qrcode, sys
q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_H, border=0)
q.add_data(sys.argv[1]); q.make(fit=True)
m = q.get_matrix(); n = len(m)
c = n / 2; rh = n * 0.165          # hole radius in modules
def in_finder(x, y): return (x < 7 and y < 7) or (x >= n-7 and y < 7) or (x < 7 and y >= n-7)
def in_hole(x, y): return (x + .5 - c) ** 2 + (y + .5 - c) ** 2 < (rh + .35) ** 2
W = n + 2
out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 {W} {W}" fill="currentColor" data-hole="{rh / W:.4f}">']
for y in range(n):
    for x in range(n):
        if m[y][x] and not in_finder(x, y) and not in_hole(x, y):
            out.append(f'<circle cx="{x+.5}" cy="{y+.5}" r=".44"/>')
for fx, fy in ((0, 0), (n-7, 0), (0, n-7)):
    out.append(f'<rect class="eye" x="{fx+.5}" y="{fy+.5}" width="6" height="6" rx="2.6" fill="none" stroke="currentColor" stroke-width="1"/>')
    out.append(f'<circle class="eye" cx="{fx+3.5}" cy="{fy+3.5}" r="1.55"/>')
out.append('</svg>')
print(''.join(out))
