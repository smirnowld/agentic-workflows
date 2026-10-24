# ADR-0002: A designer builds screens from briefs that state intent

**Status:** accepted

## Decision

A designer role builds new screens and flows as self-contained mock-ups, screenshots its own work and fixes what it sees before review. It runs on Opus; when the maintainer judges a result "Not there", the second attempt runs on Fable. The route changes only when a new model comes out. Codex is not on the route: its sandbox can't run a browser, so it can't see its own work without a sandbox exception. Design is part of the spec, before Ready: the PM launches the designer as a subagent, as it does the explorer and the critics (it still starts no coordinators), the maintainer judges each result, and, once routing.json has a designer route, an item with screens enters Ready only with a design the maintainer approved.

- **Brief.** The PM writes it, not the maintainer: it asks the maintainer about a real moment one question at a time, each with its own best guess from the spec and one or two other options to pick from or correct, drafts the brief from the answers, the spec, the strategy and the project's files, and the maintainer reacts to the draft. A design brief names the person, the moment, the one question they are asking and how they should feel; a taste bar of two or three named apps, whose look isn't copied; the states that must show, healthy ones included; platforms and frames; facts in an appendix marked as not a list to put on screen; and permission to challenge the brief. The spec critic refuses a brief that is a field list or has no person and moment, and the designer flags gaps before it starts. Each project has a design system file and a copy style file; when either is missing, the designer stops. The PM then asks the maintainer what works and what doesn't in the current product, and the designer drafts the file from those answers as directions for the maintainer to choose from. Copying the current product is a choice the maintainer makes, never the default.
- **Stages.** One stage by default: a full build of every state, on phone and desktop, in light and dark. Directions come first, as two or three key frames with notes for the maintainer to pick from or mix, only when the project has no design system yet, the screen or flow is new and options are wanted, or the maintainer asks. The PM publishes each result as a page; the maintainer judges it in plain words, and the PM turns that into feedback for the designer, never as wording to put on screen. The maintainer sees the approved design as that page; the agents read its HTML from a secret gist under their own account, linked from the item. A secret gist opens for anyone with the link, so it lives only until the item is accepted, then the PM deletes it. Designs are never committed to a repository.
- **Rules.** No flat pages: depth, contrast, separation and one accent. Styled controls, never native dropdowns or radio buttons. Desktop is its own layout, not a stretched phone screen. Show what is healthy as well as what is broken. Mock-ups don't flatter: no brand-tinted wallpaper or device chrome. Copy never repeats the brief's wording, never invents facts (names, refunds, dates) and has no machine-written tells.
- **Checks.** The designer checks its copy against the copy style, and the visual reviewer checks it again. The visual reviewer judges only what can be checked (states, sizes, contrast, copy); taste is the maintainer's. After the build, the visual reviewer compares the screens with the approved design.

## Context

In blind side-by-side runs on real screens, briefs that listed what to show failed for every model, and briefs built around a person and a moment lifted the results; a one-shot build from such a brief landed without a directions stage. Every model drifted towards flat pages and machine-sounding copy unless told otherwise. Screen briefs take longer to write, and each project carries two more files.

## Options considered

- **Sonnet or Codex as designer**: rejected. Sonnet plays safe on new screens; Codex's taste was weaker and its sandbox has no browser.
- **Fable as default, or always two stages**: rejected. Fable is uneven and costs several times as much; the brief mattered more than the stages.
- **A separate brief critic, or the visual reviewer reading briefs**: rejected. The spec critic already reads specs cold.
