# 03 · Top panels: tapping above closes them too: report

Build 1.8.0+107. `flutter analyze` is clean and `flutter test` passes (1676 tests). **Not installed on the phone yet:** wireless debugging dropped during the install, so there are no screenshots and no phone check at 115%.

## What changed
1. **Above the panel:** while the stopwatch or 4/4 panel is open, everything above it (the title, empty space, the status bar, the tuner, settings and the other panel's button) catches touches. A tap there only closes the panel. Nothing opens and nothing underneath reacts. The top row stays visible and sharp (it isn't dimmed). A long-press or a drag there does nothing at all: the panel stays open.
2. **Own button and Back:** the panel's own button closes it back into the button (the shrink, as before). Back and the predictive back gesture also keep that motion.
3. **Any other tap outside** (above the panel, on the dim below or beside it, or on the grab strip's outside part) closes it with the plain leave: full size, fade out while moving 6px up, ~180ms. Swipe-to-close is unchanged. With Remove animations on it's instant.
4. **The other panel's button** only closes the open panel, with the plain leave. It doesn't open the other one; a second tap does.

Tests cover each case for both panels: own button, Back, the other button, tuner, settings, title, empty space above, the dim below, a long-press above, and Remove animations.

## Decisions
- The catcher covers the panel's own button too, and a tap is matched to it by position (its rect when the panel opened). The button itself no longer gets the tap while the panel is open, so it shows no press ripple on close.
- A long-press above the panel neither closes it nor reaches the button. On the dim, any touch still closes, as before.

## For the designer
- **Bottom panels (set panel, Songs list, pickers):** the edited "Open and close from the button (all panels)" line now says a tap outside uses the plain leave, but the plain leave is only described for top panels ("6px move up"). I left bottom panels as they were (they shrink back toward the center button on a dim tap). Should they also use a plain leave, and should it move 6px down?

## Phone checks (to do once the phone is back, at 115%)
- With each panel open: tap the title, the tuner, settings and the other panel's button. Each should only close the panel, fading upward.
- Tap the panel's own button: it should shrink back into the button. Back should do the same.
- Long-press settings with a panel open: nothing should happen.
