#!/usr/bin/env python3

# --------------------------------------------------------------------
# Fastfetch animations
# --------------------------------------------------------------------

import os, random, re, shutil, sys, time, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = open(os.path.join(HERE, "logo.txt")).read().rstrip("\n").split("\n")
PAD_TOP, PAD_LEFT = 3, 2
FPS = 40
DECODE, SWEEP = 0.5, 0.7
NOISE = ".,:;'`-~"

BRIGHT, NORMAL, DIM, FAINT = "\x1b[1;97m", "\x1b[1;37m", "\x1b[90m", "\x1b[2;90m"
RESET = "\x1b[0m"
CSI = re.compile(r"\x1b\[([0-9;?]*)([@-~])")

def reach(line):
    col = far = pos = 0
    wrap = True
    for m in list(CSI.finditer(line)) + [None]:
        text = line[pos:m.start() if m else len(line)]
        for ch in text:
            if ch == "\r":
                col = 0
            elif unicodedata.combining(ch) or ch in "\x1b\n":
                pass
            else:
                col += 2 if unicodedata.east_asian_width(ch) in "WF" else 1
            if wrap:
                far = max(far, col)
        if m is None:
            break
        if m.group(1) == "?7" and m.group(2) in "hl":
            wrap = m.group(2) == "h"
        n = int(m.group(1).split(";")[0] or 1) if m.group(1)[:1] != "?" else 0
        op = m.group(2)
        if op == "C":
            col += n
        elif op == "D":
            col = max(0, col - n)
        elif op == "G":
            col = n - 1
        pos = m.end()
    return far


def frame(t):
    width = max(len(r) for r in LOGO)
    rows = []
    for y, row in enumerate(LOGO):
        out = []
        for x, ch in enumerate(row.ljust(width)):
            if ch == " ":
                out.append(" ")
                continue
            if t < DECODE:
                reveal = DECODE * (y + random.random() * 2) / (len(LOGO) + 2)
                if t < reveal:
                    out.append(FAINT + random.choice(NOISE))
                    continue
                out.append(NORMAL + ch)
                continue
            p = (t - DECODE) / SWEEP * (width + len(LOGO)) - 4
            d = abs(x * 0.5 + y - p)
            out.append((BRIGHT if d < 1.5 else NORMAL if d < 4 else DIM) + ch)
        rows.append("".join(out) + RESET)
    return rows


def main():
    output = sys.stdin.read()
    sys.stdout.write(output)
    sys.stdout.flush()

    lines = output.count("\n")
    size = shutil.get_terminal_size()
    if not sys.stdout.isatty() or lines > size.lines - 1:
        return
    if max(map(reach, output.split("\n")), default=0) > size.columns:
        return

    w = sys.stdout.write
    up = lines - PAD_TOP
    down = up - len(LOGO)
    w("\x1b[?25l")
    try:
        start = time.monotonic()
        while (t := time.monotonic() - start) < DECODE + SWEEP:
            buf = [f"\x1b[{up}A"]
            for row in frame(t):
                buf.append(f"\r\x1b[{PAD_LEFT + 1}G{row}\n")
            if down > 0:
                buf.append(f"\x1b[{down}B")
            w("".join(buf) + "\r")
            sys.stdout.flush()
            time.sleep(1 / FPS)
        buf = [f"\x1b[{up}A"]
        for row in LOGO:
            buf.append(f"\r\x1b[{PAD_LEFT + 1}G{NORMAL}{row}{RESET}\n")
        if down > 0:
            buf.append(f"\x1b[{down}B")
        w("".join(buf) + "\r")
    except KeyboardInterrupt:
        pass
    finally:
        w("\x1b[?25h\x1b[?7h")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
