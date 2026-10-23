---
name: bugfix
description: Use when fixing a reported Metra bug or regression ("X is broken", "it does Y instead of Z", a crash, a wrong timing or layout).
---

# Bug fix

1. **Reproduce first.** Write a test that fails for the reported reason (widget test, controller test with the fake clock, or a scheduler test). If it can't be reproduced in a test, say how it was reproduced instead (device, steps) before changing code.
2. **Find the root cause.** Grep every caller of what you'll change; fix it once in the shared code, not at one call site.
3. **Fix**, then confirm the new test passes and fails again without the fix.
4. `flutter analyze` and `flutter test` clean; a "Recent decisions" note in PLAN.md if behavior or a decision changed; bump the build number if it's installed for the user; commit `fix: ...`.
5. Report the cause in one or two plain sentences, what the test checks, and whether a device check is worth it.

If the "bug" is actually the spec's intended behavior, say so and point to the spec line instead of changing it.
