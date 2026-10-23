---
name: flutter-internals
description: Use when Metra needs Flutter framework behavior beyond the usual widgets - custom routes and barriers, panels over a usable screen, predictive back, route animations and removal, gesture arena and drag slop, or semantics blocking - before reading the framework source again.
---

# Flutter behaviors we had to look up

Flutter source: `$(flutter --version --machine | python3 -c "import json,sys;print(json.load(sys.stdin)['flutterRoot'])")/packages/flutter/lib/src/`. Check the installed version there before relying on a private detail.

- **A route that lets touches through** (top panels: the top row stays usable): subclass `PopupRoute` and override `buildModalBarrier()` to return `BlockSemantics(child: IgnorePointer(child: SizedBox.expand()))`. Areas of the page with nothing hit-testable pass touches to the routes below; the `BlockSemantics` keeps screen readers in the panel. `BlockSemantics` inside the page does not work: the page is its own semantics container.
- **Route durations are fixed at creation:** `TransitionRoute.createAnimationController` reads `transitionDuration` / `reverseTransitionDuration` once. To close without the reverse animation, call `navigator.removeRoute(route)` (no animation; the push future completes).
- **Predictive back for custom routes:** the route's `handle*BackGesture` methods are only called by `PredictiveBackPageTransitionsBuilder`. For our panels, a `WidgetsBindingObserver` (`handleStartBackGesture` returning true only while its route `isCurrent`, then update / commit / cancel) gets the gesture; it needs `android:enableOnBackInvokedCallback="true"` (set). `PredictiveBackEvent` is in `package:flutter/services.dart`.
- **Popping safely:** a second finger or a late callback can pop the route below. Pop only `if (route.isCurrent)`; after a swap or a test, check `route.isActive` before trusting a stored route.
- **Drag slop:** drags start after ~18 px (`kTouchSlop`) and by default the first delta excludes it. For 1:1 following use `dragStartBehavior: DragStartBehavior.down`.
- **Hit testing outside a box:** a `Stack` child outside its parent's bounds isn't hit-testable. To grab past an edge, grow the layout box (transparent padding) and put the detector inside it (see `PanelMotionState.panel`).
- **Claiming touches:** an opaque `Listener` sees every pointer that starts on it; pair it with a do-nothing `GestureDetector` (tap + pan, `excludeFromSemantics: true`) so no recognizer behind wins the gesture (`CloseOnTouch`).
- **Text line boxes:** `height: 1` with the default proportional leading splits the missing leading by ascent : descent; fonts with a tall ascent sit high. `TextLeadingDistribution.even` (style, `StrutStyle`, `TextHeightBehavior`) centres the font's box (see the visual-check skill).
- **A tight box stretches a button:** `OutlinedButton(fixedSize: ...)` inside a tight `SizedBox(height: 48)` is drawn 48 tall; centre it (`Center`) so the 48 dp tap target is invisible padding.
- **`IgnorePointer` and semantics:** use `ExcludeSemantics` for things that leave (fading copies), `BlockSemantics` for modal layers.
