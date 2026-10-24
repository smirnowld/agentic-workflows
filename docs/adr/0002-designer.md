# ADR-0002: A designer builds screens from briefs that state intent

**Status:** accepted

## Decision

A designer role builds new screens and flows as self-contained mock-ups, screenshots its own work and fixes what it sees before review. It runs on Opus; when the maintainer judges a result "Not there", the second attempt runs on Fable. The route changes only when a new model comes out. Codex is not on the route: its sandbox can't run a browser, so it can't see its own work without a sandbox exception.

- **Brief.** A design brief names the person, the moment, the one question they are asking and how they should feel; a taste bar of two or three named apps, whose look isn't copied; the states that must show, healthy ones included; platforms and frames; facts in an appendix marked as not a list to put on screen; and permission to challenge the brief. The spec critic refuses a brief that is a field list or has no person and moment, and the designer flags gaps before it starts. Each project has a design system file and a copy style file; when either is missing, the designer stops and drafts it for the maintainer to approve.
- **Stages.** One stage by default: a full build of every state, on phone and desktop, in light and dark. Directions come first, as two or three key frames with notes for the maintainer to pick from or mix, only when the project has no design system yet, the screen or flow is new and options are wanted, or the maintainer asks.
- **Rules.** No flat pages: depth, contrast, separation and one accent. Styled controls, never native dropdowns or radio buttons. Desktop is its own layout, not a stretched phone screen. Show what is healthy as well as what is broken. Mock-ups don't flatter: no brand-tinted wallpaper or device chrome. Copy never repeats the brief's wording, never invents facts (names, refunds, dates) and has no machine-written tells.
- **Checks.** The designer checks its copy against the copy style, and the visual reviewer checks it again. The visual reviewer judges only what can be checked (states, sizes, contrast, copy); taste is the maintainer's.

## Context

In blind side-by-side runs on real screens, briefs that listed what to show failed for every model, and briefs built around a person and a moment lifted the results; a one-shot build from such a brief landed without a directions stage. Every model drifted towards flat pages and machine-sounding copy unless told otherwise. Screen briefs take longer to write, and each project carries two more files.

## Options considered

- **Sonnet or Codex as designer**: rejected. Sonnet plays safe on new screens; Codex's taste was weaker and its sandbox has no browser.
- **Fable as default, or always two stages**: rejected. Fable is uneven and costs several times as much; the brief mattered more than the stages.
- **A separate brief critic, or the visual reviewer reading briefs**: rejected. The spec critic already reads specs cold.
