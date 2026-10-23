# Contributing

Metra is built with Claude Code from the design spec. The working rules are in [CLAUDE.md](CLAUDE.md) (audio timing, architecture, workflow) and the plan and decisions in [PLAN.md](PLAN.md). The design lives in `docs/design/` (`ui-spec.md` and its `*.reference.html` files) and is owned by the designer.

Runbooks (also used as Claude Code skills, in `.agents/skills/`):

- [feature-from-spec](.agents/skills/feature-from-spec/SKILL.md): building a feature from the spec.
- [bugfix](.agents/skills/bugfix/SKILL.md): a failing test first, then the fix.
- [data-format-change](.agents/skills/data-format-change/SKILL.md): anything that changes what the app saves (migration, version bump, snapshot).
- [release](.agents/skills/release/SKILL.md) and [RELEASING.md](RELEASING.md): shipping a build.
- [device-qa](.agents/skills/device-qa/SKILL.md): what to check on a real phone; [phone](.agents/skills/phone/SKILL.md): installing and inspecting over adb.
- [visual-check](.agents/skills/visual-check/SKILL.md): pixel-level alignment (with `tool/font_metrics.py`).
- [flutter-internals](.agents/skills/flutter-internals/SKILL.md): framework behaviors we had to look up.

Start with [ARCHITECTURE.md](ARCHITECTURE.md) (code map, glossary) and [TESTING.md](TESTING.md) (test pitfalls).

Every change ships with its tests; `flutter analyze` and `flutter test` must pass before it's committed. Record user-visible changes under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
