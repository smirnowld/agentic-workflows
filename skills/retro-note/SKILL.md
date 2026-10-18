---
name: retro-note
description: Record a one-line note about what went wrong in this session, for the retro. The maintainer calls it mid-session with the line.
---

The maintainer gives you one line on what was wrong. Record it; do not try to fix the process.

1. Read the environment variable `AGENTIC_RETRO_NOTES` (`printenv AGENTIC_RETRO_NOTES`). If it is unset or empty, say so and stop; do not guess a place to write.
2. The file is `$AGENTIC_RETRO_NOTES/YYYY-MM-DD.md` (today's date, local). Create the directory if missing. Append; never overwrite.
3. Append one entry:

```
## HH:MM

- Note: THE MAINTAINER'S LINE, verbatim
- Session: SESSION ID
- Repository and branch: REPO, BRANCH
- Doing: TWO SENTENCES on what this session was doing when it went wrong.
```

Get the repository and branch from `git remote get-url origin` and `git branch --show-current`; the session id from the session's environment or its transcript name, or write "unknown" if you cannot find it.
4. Confirm in one line with the file path. Then carry on with the session's work.
