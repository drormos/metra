---
name: feature-from-spec
description: Use when building or changing a Metra feature from the designer's prompt or docs/design/ui-spec.md (a new screen, panel, control, behavior or motion described in the spec or a *.reference.html).
---

# Feature from the spec

1. **Read.** ARCHITECTURE.md (where things live), the Principles section of `docs/design/ui-spec.md`, the section the prompt names, and every `*.reference.html` it points to (sizes and colors come from there; don't port markup). Check CLAUDE.md's audio rules if timing or sound is involved.
2. **Conflicts.** If the request breaks a principle or contradicts the spec or a reference, say so and ask in plain product terms instead of guessing. Technical choices are yours: decide and record them.
3. **Plan.** List what changes and where (controller, model, UI), reusing what exists (`PanelMotion`, `Segmented`, `ValueStepper`, theme tokens; colors only from the theme).
4. **Tests first** for behavior and timing (fake clock: `test/audio/fake_click_output.dart`), then implement. Large text, Daylight and "Remove animations" must hold (a11y guideline tests).
5. **Saved data touched?** Follow the data-format-change skill.
6. `flutter analyze` and `flutter test` clean; add an entry under "Recent decisions" in PLAN.md (decisions, not a diary; update ARCHITECTURE.md if a module, file role or spec term changed); bump the build number if it will be installed for the user; commit (message ends with the Co-Authored-By line).
7. Report: what changed, decisions made, and only the device checks worth doing (see device-qa).

Never edit `docs/design/` (the spec and references are the designer's) unless the prompt explicitly says to.
