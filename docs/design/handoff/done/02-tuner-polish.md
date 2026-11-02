# 02 · Tuner polish (after build 105 review)

Spec: ui-spec.md › Tuner › Layout ("A4 =", "Sizes (build 105 review)", "Sharps"). Re-read it first.

1. Reference row: one line, "A4 =" then the 430–450 Hz stepper (replaces "Reference A4", which wrapped at 115% on 360dp).
2. Bigger: note ~200dp tall (use the empty space above it), meter 88dp tall and full width, needle 4dp (6dp in tune). Keep everything on one screen at 115% on a 360dp phone without scrolling.
3. Sharps: ♯ and octave in one small column right of the letter (♯ at cap height, octave at baseline), tight to the letter, the group centered. Same for ♭.

Tests for the layout at 115% on 360dp and on a normal phone. Screenshots (sharp, in tune, silent) into docs/design/screens/, named tuner-*-v2-115.png. If the phone is connected, also do the phone checks listed in reports/01-tuner.md and report what you saw.
