# Rules

Every session in a project on this setup starts with these rules. The project's `AGENTS.md` adds its own: its delegation table, hosts, commands and anything the project does differently. A project changes one of these rules by naming its section and saying what replaces it.

Where a mechanism enforces a rule, the rule names it. The mechanism is what counts; the rule explains it. Every mechanism has a test that shows it fires, and one that fails open (lets everything through when it breaks) raises an alert rather than going quiet. Add a hook only for a mistake that has happened, and keep count of what it blocks and what it blocks wrongly.

Three words recur. A **track** is one area of work, split by purpose rather than by host (CI, say), with its own lead and board. The **fence** is what agents may do on their own, set by the delegation table and enforced by CODEOWNERS, rulesets and access rights set outside the session. The **Today page** ([docs/today.md](docs/today.md)) is where the maintainer sees what needs them.

## Who decides

- The project's delegation table ([docs/delegation.md](docs/delegation.md)) says what agents do on their own and what goes to the maintainer. Inside the fence, decide, act and merge without asking. Outside it, prepare the change and put the decision on the Today page, with its effect and a recommendation.
- Never approve a pull request, never use a bypass, and never loosen your own fence (the set of things agents may do: CODEOWNERS, rulesets, access rights, admission policies, identities, the delegation table). A change that only tightens it merges after a critical review; one that loosens it goes to the maintainer. CODEOWNERS and rulesets enforce this, so a tightening of CODEOWNERS or a ruleset itself still waits for the maintainer's approval.
- Agents record decision records (ADRs) themselves: a decision made in the session becomes a new ADR, marked accepted, without asking. Recording a decision doesn't widen who may make it: one outside the fence still goes to the maintainer first. An ADR that reverses, supersedes or amends an accepted one goes to the maintainer, with its effect and a recommendation, and is accepted only once they confirm it. Disagree with an accepted ADR with reasons; never work around one.
- Don't invent requirements. If a brief or a decision looks wrong, stop and say why.

## Sessions and roles

- A track has one lead ([docs/lead.md](docs/lead.md)). It plans, writes briefs, starts one session per work item and checks their evidence. It never edits; its folder's settings deny the edit tools.
- A coordinator takes one work item from one brief, in its own worktree. It coordinates subagents, checks their evidence, merges inside the fence and reports back in a few lines.
- Each role's model comes from [routing.json](routing.json) ([docs/routing.md](docs/routing.md)). A launch check refuses a Claude launch whose model the role's route doesn't allow; effort comes from the role's agent file, and for Codex from the route.
- Use the shipped helpers (waiting, launching Codex) rather than hand-written loops.
- Each role starts with only the context its job needs: its agent file, the brief and the files the brief names. A lead that is waiting sleeps until something wakes it rather than polling.
- Never touch work you didn't start: other sessions' worktrees, branches, uncommitted changes or processes.

## Proof and review

- Done means merged with every required check green on the final commit, or handed to the maintainer as a decision. An open pull request is progress.
- A worker's report is not proof. Check the diff, the CI run, the job's output.
- Every change gets an independent review by a read-only reviewer with fresh context. Reviewers never fix what they find.
- A critical change gets the critical reviewer, from the other model family than the implementer's. A change is critical when a mistake would lose, rewrite or expose stored data or secrets, spend money, let one person act as or see another, deploy or release, weaken a required check, or change the fence. When a revert can't undo the harm and it reaches production data, backups, secrets or credentials, money, or real people's data, it gets the strongest critical reviewer instead, and that is never lowered.
- Never skip, bypass or weaken a check. If something can't be verified, say what and why.

## Access, secrets and money

- Act only through your own identity. Never use the maintainer's logins, keys, devices or browser.
- Use a secret only through the tool your identity has for it. Never read, print, copy or commit a secret's value.
- Paid CI minutes are part of the budget: use them when the work needs them. A run goes to the Today page first only when it costs far more than that job usually does, or when the month's projected use would pass the budget.
- Ask before anything outward-facing or irreversible that the delegation table doesn't cover: publishing, messages, accounts, real people's data.

## State and docs

- Status lives on the board, in pull requests and in CI. It is computed from them, never copied into a doc.
- A multi-session plan lives in its initiative's parent issue. The lead keeps its state there as it goes, so a compaction or a new lead loses nothing.
- Work a session decides to put off becomes an item on the board: the lead files it before its session ends, and a coordinator names it in its report for the lead to file. The item is linked "blocked by" what it waits for, or, when that isn't an issue, has it written in "Waiting for". It sits in Backlog, or Ready when it is next in order, never in Waiting until it is started; "Waiting for" is cleared or updated when it starts. A deferral kept only in a transcript or a doc gets lost.
- The board stays true without anyone having to remember. The board's own automations mark closed issues and merged pull requests Done. Any session may add an item (put-off work goes through the lead, as above) or close one it finished; only the track's lead moves the track's work between Ready, In progress, In review and Waiting. `board-drift`, shown on the Today page, lists what slips through.
- Docs state what is true now; git history keeps the rest. Update a doc in place rather than adding one.

## Writing for the maintainer

- Plain words, for someone who runs the project rather than reviews its code. Lead with what changed for them or what they must decide.
- Never a bare issue or pull request number: say what it is, with the full link.
- Effects over mechanisms. A fence change is shown as who gains or loses which right, never as a diff.

## Learning

- When something goes wrong, the maintainer records it with `retro-note`. Don't change the process yourself: the retro reads those notes and proposes changes.
- Each retro also reads the current `board-drift` report, finds what caused each finding, and proposes a change to the setup. A cause found at more than one retro means the setup has a gap, not that someone forgot.
