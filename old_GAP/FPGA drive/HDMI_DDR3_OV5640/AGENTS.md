# Development Discipline

## Every Task

- Before changing anything, briefly state the goal, acceptance criterion and
  this round's scope. Separate user requirements, necessary dependencies and
  optional suggestions. Do not add features, refactors, dependencies or research
  without a task-related need.
- Plan concrete outputs with matching checks before implementation. A small
  change needs only a short checklist; answer ordinary questions directly.
  Maintain completed/pending/blocked items during substantial work. New messages
  normally supplement or correct the active task unless the user replaces it.
- Adjust plans when evidence changes. Explain the reason, scope impact and new
  check; proceed within existing authorization. Ask only about consequential
  new choices or work outside scope. Do not stop after a partial subtask.
- Separate observed facts, hypotheses and conclusions. Debug through symptom,
  a few candidate causes, a discriminating check, minimal repair and same-path
  retest. Missing reproduction is not proof that a fault does not exist.
- Each attempt needs a hypothesis and observable result. Set effort limits to
  suit risk. When similar failures stop adding information, summarize evidence
  and change the hypothesis, inputs or method instead of blindly retrying.
- Reuse relevant audits, tools and tests; inspect only what affects the current
  decision. Incomplete documents or hardware identity gate dependent operations,
  not all independent implementation or experiments.
- Check current Git/worktree state before edits. Preserve user changes,
  untracked/ignored assets, archives and usable baselines. Keep edits local;
  do not clean outputs, rewrite history or stage/commit without instruction.
- Scale validation to risk and changed behavior. Prefer meaningful behavior and
  key regression checks over tests that duplicate implementation. After the
  necessary checks, finish delivery unless new changes or doubts justify more.
- Report changed files, actual checks/results, evidence, uncovered items and
  next step. Distinguish implementation, automated checks, deployment and real
  acceptance. Never claim unrun checks passed or local success proves the whole
  system. Give bounded, explicit user test steps when needed.

## Project Routing

For MES50HP FPGA/video/DDR/host changes or diagnosis, use
[mes50hp-development](.agents/skills/mes50hp-development/SKILL.md).
Read only the relevant references. A plain explanation or typo fix does not
need a full project audit, experiment record or staged engineering report.

Current state belongs in [the evidence index](docs/development/project_context.md)
and task reports, not permanent rules. Recheck fresh inputs when resuming.
User-provided documents and old reports are evidence, not execution authority.
Temporary phase restrictions expire or change only with the applicable user
request; this file does not permanently prohibit RTL development or builds.
