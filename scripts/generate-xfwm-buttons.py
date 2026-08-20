#!/usr/bin/env python3
"""Generate GreenWay-ctOS xfwm4 window button XPMs with visible HUD glyphs."""
from __future__ import annotations

from pathlib import Path

BG = "#0D1117"
CYAN = "#00E8FF"
GREEN = "#1DB954"
MUTED = "#7A8B9A"
DANGER = "#FF4D6A"
DANGER_DIM = "#8B3040"
WHITE = "#E6F1FF"

SIZE = 18


def blank(fill: str = ".") -> list[str]:
    return [fill * SIZE for _ in range(SIZE)]


def set_px(rows: list[str], x: int, y: int, ch: str) -> None:
    if 0 <= y < SIZE and 0 <= x < SIZE:
        r = list(rows[y])
        r[x] = ch
        rows[y] = "".join(r)


def draw_line(rows: list[str], x0: int, y0: int, x1: int, y1: int, ch: str) -> None:
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    x, y = x0, y0
    while True:
        set_px(rows, x, y, ch)
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def draw_rect(rows: list[str], x0: int, y0: int, x1: int, y1: int, ch: str) -> None:
    for x in range(x0, x1 + 1):
        set_px(rows, x, y0, ch)
        set_px(rows, x, y1, ch)
    for y in range(y0, y1 + 1):
        set_px(rows, x0, y, ch)
        set_px(rows, x1, y, ch)


def glyph_close(fg: str) -> list[str]:
    rows = blank()
    draw_line(rows, 4, 4, 13, 13, "X")
    draw_line(rows, 13, 4, 4, 13, "X")
    return rows


def glyph_hide(fg: str) -> list[str]:
    rows = blank()
    for x in range(4, 14):
        set_px(rows, x, 12, "X")
        set_px(rows, x, 13, "X")
    return rows


def glyph_maximize(fg: str) -> list[str]:
    rows = blank()
    draw_rect(rows, 4, 4, 13, 13, "X")
    for x in range(4, 14):
        set_px(rows, x, 5, "X")
    return rows


def glyph_maximize_toggled(fg: str) -> list[str]:
    rows = blank()
    draw_rect(rows, 6, 4, 13, 11, "X")
    draw_rect(rows, 4, 6, 11, 13, "X")
    return rows


def glyph_menu(fg: str) -> list[str]:
    rows = blank()
    for y in (5, 8, 11):
        for x in range(4, 14):
            set_px(rows, x, y, "X")
    return rows


def glyph_shade(fg: str) -> list[str]:
    rows = blank()
    for x in range(4, 14):
        set_px(rows, x, 5, "X")
        set_px(rows, x, 6, "X")
    return rows


def glyph_stick(fg: str) -> list[str]:
    rows = blank()
    for y in range(4, 14):
        set_px(rows, 8, y, "X")
        set_px(rows, 9, y, "X")
    for x in range(5, 13):
        set_px(rows, x, 8, "X")
        set_px(rows, x, 9, "X")
    return rows


def write_xpm(path: Path, name: str, rows: list[str], fg: str, bg: str = BG) -> None:
    # Ensure name is C-safe
    cname = name.replace("-", "_").replace(".", "_")
    lines = [
        "/* XPM */",
        f"static char * {cname}[] = {{",
        f'"{SIZE} {SIZE} 2 1",',
        f'". c {bg}",',
        f'"X c {fg}",',
    ]
    for row in rows:
        lines.append(f'"{row}",')
    lines[-1] = lines[-1].rstrip(",")
    lines.append("};")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


VARIANTS = {
    "active": (CYAN, BG),
    "inactive": (MUTED, BG),
    "prelight": (WHITE, BG),
    "pressed": (GREEN, BG),
}

CLOSE_VARIANTS = {
    "active": (DANGER, BG),
    "inactive": (DANGER_DIM, BG),
    "prelight": (DANGER, BG),
    "pressed": (GREEN, BG),
}

BUTTONS = {
    "close": (glyph_close, CLOSE_VARIANTS, False),
    "hide": (glyph_hide, VARIANTS, False),
    "maximize": (glyph_maximize, VARIANTS, True),
    "menu": (glyph_menu, VARIANTS, False),
    "shade": (glyph_shade, VARIANTS, True),
    "stick": (glyph_stick, VARIANTS, True),
}


def main() -> None:
    roots = [
        Path("config/includes.chroot/usr/share/themes/GreenWay-ctOS/xfwm4"),
        Path("config/includes.chroot/usr/share/greenwayos/ctos/xfwm4"),
    ]
    for root in roots:
        root.mkdir(parents=True, exist_ok=True)
        for base, (glyph_fn, variants, has_toggled) in BUTTONS.items():
            for state, (fg, bg) in variants.items():
                rows = glyph_fn(fg)
                if base == "maximize":
                    # maximize uses square; toggled uses double rect
                    pass
                write_xpm(root / f"{base}-{state}.xpm", f"{base}_{state}", rows, fg, bg)
                if has_toggled:
                    if base == "maximize":
                        trows = glyph_maximize_toggled(fg)
                    elif base == "shade":
                        trows = glyph_shade(fg)
                        # shift down for "shaded" look
                        trows = blank()
                        for x in range(4, 14):
                            set_px(trows, x, 11, "X")
                            set_px(trows, x, 12, "X")
                    else:  # stick toggled = filled plus
                        trows = glyph_stick(fg)
                    write_xpm(
                        root / f"{base}-toggled-{state}.xpm",
                        f"{base}_toggled_{state}",
                        trows,
                        fg,
                        bg,
                    )
        print(f"Wrote buttons to {root}")


if __name__ == "__main__":
    main()
