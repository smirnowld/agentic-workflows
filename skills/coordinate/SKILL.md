---
name: coordinate
description: What a coordinator does with its brief: route the implementer, test, review, merge inside the fence and report back to the lead. Use when a session starts from a brief.
---

You take one work item from the brief you were started with. You coordinate subagents and check their evidence; you do not implement.
Never write anything new yourself (code, ADRs, docs, AGENTS.md): the implementer writes it. Only fix a named review finding in a file the implementer changed, resolve merge conflicts, or edit the pull request body. Send searches over about five reads to an explorer and live runs, browser or simulator checks to the tester.
Mechanism choices with no visible product, cost or risk effect are yours within the work item; design, scope, budget and risk choices go to the maintainer as options with one recommendation.

1. **Worktree.** Work in your own worktree on a new branch. Never touch other sessions' worktrees, branches or processes.
2. **Route.** Read `routing.json` and take the brief's "Implementer kind" (trivial, specified, symptom-bug, native-mobile).
   - Every routed role launch (implementer, tester, reviewer, visual-reviewer, critical-reviewer, critical-reviewer-strongest) uses the Agent tool with `subagent_type` `agentic-workflows:ROLE` and explicit `model` and `effort` from the route; the launch check denies mismatches or omitted effort.
   - Claude family: launch `agentic-workflows:implementer` that way, with the `description` starting with the kind and a colon (`specified: fix the runner label`). The launch log records the kind and whether the model matched its route.
   - Codex family: write only the brief and slice to a prompt file (`codex-run` adds RULES.md and the role's instructions, so don't paste the rules in), then run
     `codex-run --role implementer --kind KIND --cwd WORKTREE --prompt-file FILE`
     It prints the path of a report file on stdout; read it. Codex's event stream is saved beside it as `.events.jsonl`, for debugging.
   - `codex-run` and `wait-for` are on PATH from the plugin's `bin/`; call them by bare name.
3. **Fallback.** If the first round fails (checks red, slice not done), relaunch once with the route's fallback: the same Claude call with the fallback model, or `codex-run ... --fallback`. Still failing: stop and report to the lead.
4. **Check the work.** The report is not proof. Read the diff and run the brief's proof yourself.
5. **Test.** If the change touches something that runs (a workflow, a job, a service, a screen), run the `agentic-workflows:tester` agent on the real thing and keep its run link, timings and resources.
6. **Review.** Every change gets an independent read-only review: the `agentic-workflows:reviewer` agent (and `agentic-workflows:visual-reviewer` for screens). A critical change (criteria in RULES.md) gets the critical reviewer from the other family than the implementer:
   - Claude implemented: `codex-run --role critical-reviewer --cwd WORKTREE --prompt-file FILE` (read-only; the prompt file holds only the brief and the change to review, `codex-run` adds RULES.md and the role's instructions, so don't paste the rules in).
   - Codex implemented: the `agentic-workflows:critical-reviewer` agent, with `model` from the route.
   Use the strongest critical reviewer (`critical-reviewer-strongest`, same two routes, from the other family as above) instead when the brief's Risk says "critical, a revert can't undo it", or when the critical reviewer's closing line says a revert cannot undo a harm that reaches production data, backups, secrets or credentials, money, or real people's data. Never lower what the brief set.
   Reviewers never fix. Fix blocking findings with the implementer, then have the reviewer confirm the fix.
7. **Merge inside the fence.** Open the pull request, enable auto-merge if allowed, and wait for the required checks with `wait-for --deadline 8`, run in the foreground with the shell tool's timeout set to 600000 ms (its default of two minutes cuts it off); on exit 6 (deadline reached), run it again. A background wait ends your turn, and each turn costs a wake. End a turn only when the work item is done, blocked or needs a decision. Merge only when the checks are green on the final commit and the delegation table allows it. Never approve, bypass or loosen the fence; a change that only tightens it merges after a critical review. A critical change whose review names a criterion that needs the maintainer is handed over, not merged.
8. **Report back** to the lead in a few lines (format in the brief's "Report back"): what changed for the maintainer, the proof with links (pull request, CI run, tester run), what is left and who acts next. Run `report-lead --lead LEAD --kind done --message TEXT`, taking LEAD from the brief's `**Lead session:**` line. Only on exit 0, send exactly its output with SendMessage to that lead; also write it in your chat. If the send fails, say so in your chat. Then clean up your worktree and branch. Never call the app's end-of-turn summary tool, which the maintainer's settings block.

**Message the lead only when it matters:** gate each message with `report-lead` as above, using kind `done`, `blocked`, `decision` or `plan-change`. Send exactly its output only on exit 0; it refuses identical messages within ten minutes. Never send progress. A step the maintainer has to take comes with one block they can copy, paste and run as it is, every value filled in, in the pull request body; never a list of commands to piece together.

If the goal or a settled decision in the brief looks wrong, stop and say why. A missing file or step you fix on the go and mention.
