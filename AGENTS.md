# Rules for changing this repository

This repository is public and describes the setup as it works now. These rules apply to every change here, on top of [RULES.md](RULES.md).

## Current state only

- Describe how things work now. No history: no earlier versions of the setup, what changed from them, lessons learned, or "this replaces". The reason for a rule is a short sentence in general terms, if it needs one.
- Open questions and plans live on the board, not in files.
- No results: measurements, counts, costs, dates of trials, trial logs, briefs and session notes stay in private places. Only the lasting conclusion lands here, as a rule or a route.

## Nothing private

- Never name the maintainer, their organisation, projects, repositories, hosts, machines or accounts, and never link them. Use generic words: "a product repository", "a server", "a desktop machine".
- First person ("I") in the README is fine; everywhere else it's "the maintainer".
- The only handle allowed is the code owner in CODEOWNERS.

## The check

`make test` runs [tests/test-public-text.sh](tests/test-public-text.sh), which fails on history words, email addresses, handles outside CODEOWNERS, and a private list of terms kept outside the repository (the `PRIVATE_TERMS` Actions secret, one term per line; in CI the check asks the runner to mask each term in the log). It scans tracked files and their paths, and in CI also the pull request's commit messages, title and body. It prints only where a hit is, never the match. It is part of the required `CI OK` check, and in CI it fails when the private list is missing, except on pull requests from forks, which get no secrets.

It can't see everything: binary files, its own file (which has to name the words it looks for), branch and tag names, commit authors, release notes, issue and board text, and comments. Keep those generic by hand. When it fires, rewrite the text; never weaken the check to let it through. A new kind of leak gets a new rule in the check, not only a sentence here.
