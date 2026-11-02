# 03 · Top panels: tapping above closes them too

Spec: ui-spec.md › Top panels ("Open and close from the button", "Above a top panel closes it too", "Which close motion"). Re-read it first.

1. While the stopwatch or 4/4 panel is open, a tap anywhere above it (title, empty space, the other top-row buttons incl. tuner and settings) only closes the panel; it never opens anything or reaches the button underneath. The top row stays visible and sharp. A long-press there does nothing either.
2. The panel's own button still closes it with the shrink-toward-the-button motion. Back keeps that motion too.
3. Any other tap outside the panel (above it, or on the dim below it) closes with the plain leave motion: fade out + 6px up, ~180ms, no shrink toward the button. Swipe-to-close is unchanged. Remove animations: instant.
4. Tapping the other panel's button (4/4 while the stopwatch panel is open, or the reverse) only closes the open panel, with the plain leave motion (no shrink toward either button); it doesn't open the other one.

Tests for each case (own button, other button, title, empty space above, dim below, Back). Check on the phone at 115%.
