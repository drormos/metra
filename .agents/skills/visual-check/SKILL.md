---
name: visual-check
description: Use when the user reports that something on Metra's screen looks off by a few pixels - misaligned, not centred, a box taller than its neighbours, text sitting high or low - or when a layout must match a reference exactly.
---

# Pixel-level fixes

1. **Measure before changing.** Find the real numbers: the widget's rect in a test (`tester.getRect`), the layout box vs the visible box (a `Material` inside a button), and for text the font metrics: `python3 tool/font_metrics.py assets/fonts/<font>.ttf` prints ascent, descent, line gap, x-height and cap height (per 1000 em).
2. **Work out the cause from the numbers**, not by nudging. Examples: a box stretched by a tight parent (centre it); text high because `height: 1` + proportional leading puts the baseline at ascent ÷ (ascent + descent) (use even leading); an icon drawn off-centre in its own box.
3. **Fix it with a rule, not a per-device offset.** If an offset is still needed, derive it from the metrics in code or a named constant with the numbers in a comment.
4. **Prove it with a test** that fails on the old code (`git stash push <file>` to check). For text, load the real font in the test (TESTING.md, "Real fonts aren't loaded") and compare distances (e.g. cap top and baseline equidistant from the box's inner edges, ±0.5 px). Test at 100 %, 130 % and 200 % text, and with the variants that change width (polyrhythm suffix, long names).
5. **Check on the phone** (phone skill): screenshot and crop the area, next to the neighbours it should match.
