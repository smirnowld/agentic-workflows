# The delegation table

Each track has a delegation table: every kind of action its agents might take, who takes it, and the mechanism that makes it so. The table lives in the track's main repository, owned by the maintainer through CODEOWNERS, and the rules point to it.

A row with no mechanism is a wish. Building the mechanism is fence work and comes first; until it exists, the row stays with the maintainer.

## Who decides

- **Agents decide, act and merge** inside the fence: the limits that mechanisms enforce (access rights, admission policies, rulesets, scoped identities). That includes running commands and using the secrets their identity holds, with checks green and an independent review passed. Recording a decision made in the session as a new decision record (ADR), marked accepted, is theirs too.
- **The maintainer decides**:
  - direction: vision, roadmap, users, design taste, high-impact standards;
  - reversing, superseding or amending an accepted ADR;
  - starting and stopping tracks;
  - budget and the split between providers;
  - anything that loosens the fence (see the pattern below);
  - irreversible or outward-facing actions: publishing, money, accounts, real people's data.

## Columns

| Column | What goes in it |
|---|---|
| Action | What is done, in words the maintainer would use. |
| Who | `agents`, `a merge` (it happens when a reviewed change merges), `agents propose, maintainer acts`, or `maintainer`. |
| Mechanism | What enforces it: a ruleset, CODEOWNERS, an admission policy, RBAC, a scoped identity, a budget check, an approval gate. |
| Today | How it works before this track moves, so the change is visible. Dropped once the track has moved. |

Group rows by area: code and merges; hosts; isolation; runs in other repositories; money and secrets.

## Patterns

Start from these.

### Inside the fence, agents merge

Docs, tests and anything outside the trust paths merge after the required checks and an independent review. Configuration the track runs on merges after a critical review. CODEOWNERS covers only the fence itself, not everything that runs.

### A merge is the deploy

If merged configuration still needs someone to apply it by hand, agents can't finish their own work. An applier inside the cluster (or the host) applies the main branch, limited to what the track owns. Nobody applies by hand, agents included.

### Root without holding root

Host changes (system services, packages, the container runtime's settings) need root. Agents don't get root or sudo. Instead a root job on each host applies reviewed scripts from the main branch, pinned to a commit. Agents get the effect of root through review and merge, and the audit trail is the git history.

### Tighten freely, loosen through the maintainer

A change that only makes something harder to reach or escape (a deny rule, a stricter runtime, removed access) can be proven before and after and undone by a revert. Agents merge it after a critical review that includes that proof.

A change that makes something easier to reach (opening a network path, granting an identity a right, giving an identity a secret, adding a host) is an agent granting itself reach. It goes to the maintainer, shown as its effect: who gains what. Each such review records whether the maintainer changed the outcome; if they never do, the retro proposes moving these to agents too.

### Runs are part of the work, within budget

Agents start and re-run workflows in the repositories the track serves, paid minutes included. Two mechanisms limit this:

- Jobs that deploy or release sit behind an environment that needs the maintainer's approval, so starting a run cannot reach them. A repository where such a job has no gate gets the gate first.
- A budget check before each paid run sends it to the Today page only when it costs far more than that job usually does, or when the month's projected use would pass the budget. The provider's spending limit stays the hard cap.

### Money, secrets and accounts

Spending limits, paid tiers, new paid services, placing and rotating secrets, and anything done with the maintainer's own logins stay with the maintainer. Agents see secrets' names, never their values, and raise an expiry 30 days ahead.

## Template

```markdown
# Delegation table: TRACK

| Action | Who | Mechanism | Today |
|---|---|---|---|
| **Code and merges** | | | |
| Merge docs, tests, other non-trust paths | agents | required checks, independent review | |
| Merge the configuration the track runs on | agents | critical review; CODEOWNERS limited to the fence | |
| CODEOWNERS, rulesets, workflow files, this table | maintainer | CODEOWNERS and a ruleset | |
| **Hosts** | | | |
| Restart, scale (within a cap) or unstick a workload | agents | admission policy for the agent identity | |
| Apply manifests | a merge | in-cluster applier, limited to the track's namespaces | |
| Change a host itself | a merge | root job applying reviewed scripts from main | |
| **Isolation** | | | |
| Tighten | agents | critical review with proof before and after | |
| Loosen | maintainer | agents prepare it and show the effect | |
| **Runs in other repositories** | | | |
| Start or re-run any workflow | agents | approval environments on deploy and release; budget check | |
| **Money and secrets** | | | |
| Budgets, paid tiers, placing or rotating secrets | maintainer | billing; secret store | |
```

## Identity and isolation

- A network identity belongs to a machine, not to a process: anything on a machine reaches what the machine can. A pull request runs its own workflow file before anyone reviews it, so every CI job counts as hostile.
- The maintainer's own devices run no agents. Agents run on a separate host as a standard user with their own credentials: none of the maintainer's keys, password manager or browser sign-ins.
- The network denies by default. Agents and runners reach only what their track needs, and never the maintainer's devices.
- Workflow files and deploy secrets are protected on the code host: code owners and a ruleset for workflow files, and deploy secrets only in environments limited to the main branch or gated by approval.
