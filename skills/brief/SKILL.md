---
name: brief
description: Fill in the brief template for one work package, to start a package session with. Use when the lead is about to start a package.
---

Write one brief for one work package from `templates/brief.md` in this plugin's repository.

1. Copy the template's sections as they are. Fill every one; write "none" where there is nothing.
2. Put conclusions, not reasoning. The receiver never sees your chat, so every fact needs its link or evidence and every settled decision its link.
3. Header: the package's issue (the pull request closes it), repository and base, the risk with what a mistake would do, and the implementer kind. Pick the kind by `docs/routing.md`: trivial (one-line fix, rename, bump), specified (clear spec: CI, tooling, server work), symptom bug (known only by what it does), native mobile (needs the native build and tests).
4. Goal: the outcome and how anyone can tell it is done.
5. Where the work is, and Don't touch: name paths and resources, including what another session holds.
6. Proof: what must be green or shown before merge, and a tester run on the real thing where the change touches something that runs.
7. Needs the maintainer: usually none. If not, write it as it will appear on the Today page.
8. Keep it to one page. A plan belongs in the initiative's parent issue, not here.

Use the result as the prompt of the new package session.
