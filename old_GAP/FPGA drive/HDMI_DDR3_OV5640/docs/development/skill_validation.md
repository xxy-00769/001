# Skill Installation and Validation

Date: 2026-10-19. Scope: project rules, one local Skill and validation support
only. No RTL, IP, FDC, build configuration, product tests, deployment or board
operations are part of this task.

## Installation

- Canonical skill: `.agents/skills/mes50hp-development/`.
- Always-on rules: repository `AGENTS.md`.
- Workspace-parent `AGENTS.md` routes only this project and related evidence.
- Workspace-parent `.agents/skills/mes50hp-development` links to the canonical
  folder. It must not become a copied second version.
- No global AGENTS, user skills or Codex configuration were changed.
- `agents/openai.yaml` explicitly permits implicit invocation. The description
  targets this project, not every FPGA question or unrelated repository.

The general discipline lives in `AGENTS.md` and the portable workflow reference.
Architecture, command selection, hardware gates and specialized acceptance live
in the project references. Changing status and issues live in project documents.
No existing local project AGENTS/Skill was found to merge during initial search;
built-in skill-creator was reused instead of creating an installer framework.

## Validation Levels

Earlier results are retained in [checks_01.json](validation/checks_01.json) and
[checks_02.json](validation/checks_02.json). The final post-document-update
result is `validation/checks_03.json`.
The script checks frontmatter, automatic invocation policy, local references,
preservation of preexisting files and the read-only Codex `skills/list` endpoint.
It never starts a thread or turn.
The before manifest protects 331 preexisting tracked/nonignored untracked files
plus all source files, HEAD and index. It is a scoped change check, not a new
recoverable backup or a hash audit of all ignored outputs/outside archives.

| Check | Actual result and boundary |
| --- | --- |
| Built-in `quick_validate.py` | PASS: `Skill is valid!`; naming/frontmatter/scaffold check only |
| Metadata and automatic matching policy | PASS; one project-specific name, implicit invocation enabled |
| Markdown local reference targets | PASS; existing targets resolved from the referencing file |
| Real loader, Codex `0.163.0-alpha.10.2` | PASS: `skills/list` from entrance, repository and `source/rtl` each returns exactly one enabled canonical skill and no discovery errors |
| New textual files whitespace | `git diff --no-index --check` emitted no whitespace errors; no index changes |
| HEAD and Git index | Unchanged from the pre-edit manifest |
| Preexisting content comparison | NOT fully unchanged: 330/331 preserved; `source/rtl/wr_cmd_trans.v` changed externally during the task |

The observed source difference adds `read_en &&` to the completion condition.
Before SHA256: `CCAA77338301EF6416F48B7AACDD6881BF5E8970D1E0575C41E45B79F826CA86`.
Observed after SHA256: `2B99C581904A5C61FAA6EA8BF06065482A724A72C01CB4EF56FE86E53443F659`.
This side conversation issued no product-code patch and did not revert or test
that change. New `tools/s3a_wr_completion/` files also appeared externally;
they are not Skill deliverables. The JSON's overall `passed: false` is retained
because its preservation check failed; it does not negate the independent
successful static/loader checks. Do not alter the baseline or whitelist the
change merely to obtain an all-green result.

The intermediate `checks_02.json` also caught a premature Markdown link to its
own not-yet-written output. That record is retained; the final-result path is
now plain code text so the reference check does not require an output to exist
before producing it. No failed evidence was overwritten.

The first validator launch stopped before checks because the bundled Python
lacked `PyYAML`. A narrowly isolated `PyYAML==6.0.2` was installed with `--no-deps
--no-cache-dir` into workspace-parent
`tmp/skill_creator_validation_20261019_c29b7a/python`; no global/site environment,
project product dependencies or configuration were changed. This temporary
validation dependency is not part of the Skill runtime or a Git-only checkout.

Recheck command, using the same local tools and a new output filename:

```powershell
$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = 'E:/FPGA drive/tmp/skill_creator_validation_20261019_c29b7a/python'
& 'C:/Users/19511/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B `
  './docs/development/validate_skill.py' `
  --validator 'C:/Users/19511/.codex/skills/.system/skill-creator/scripts/quick_validate.py' `
  --codex 'C:/Users/19511/AppData/Local/OpenAI/Codex/bin/e78bad9887fa50cf/codex.exe' `
  --output './docs/development/validation/checks_04.json'
```

The script does not overwrite existing outputs. The source-preservation check
compares against this installation's before manifest, so later legitimate
product edits can also produce a failed comparison; interpret each check rather
than treating this script as a product CI or generic whole-worktree approval.

## Manual Scenario Review

These are desk reviews of the instructions, not independent agent executions.

| Scenario | Expected route and acceptance |
| --- | --- |
| User authorizes only S3a | State single completion defect and matching check; preserve S2 failure, modify only authorized logic/tests, retest same path and nearby boundaries; do not fold in rd_buf repair or hardware actions |
| New waveform contradicts diagnosis | Mark old explanation as hypothesis, identify changed evidence and discriminating check, revise plan within scope; ask only if a material new choice is required |
| Equivalent timing attempts keep failing | Separate parameter/tool failures from actual physical attempts; stop the uninformative method, inspect valid tool inputs/topology and choose another bounded check; do not claim all methods impossible |
| Tiny documentation typo or factual code question | Direct answer or short edit/check; no full audit, backup, multi-stage plan, RTL regression or new task report |
| Photos/IO signoff incomplete | Proceed with independent unit/software/design work; gate only operations needing those hardware facts |
| MODE=0 or encoded packet offered as completion | Trace other overlays or physical ports; decline clean-color/link completion claims without the corresponding evidence |
| Historical S1-only report conflicts with later task | Use the current user's authorized scope; old stop text and proposed next stages do not grant or permanently prohibit new work |

Review outcome: the rules contain a scoped route for each scenario, including
the simple-task fast path. This does not prove a future model will follow them;
adjust narrowly after observed real use, not by accumulating speculative rules.

## Discovery and Invocation

The entrance is outside the Git root. A Windows junction was created locally
and the actual loader returned the canonical repository path from all three
tested locations, without duplicates. The link and entrance AGENTS are outside
Git; a new clone retains the canonical repository Skill but does not reproduce
that parent-directory convenience link. Prefer opening the Git root after a move,
or deliberately recreate the local link against its new verified target.

Implicit selection uses the Skill description; explicit invocation uses
`$mes50hp-development`. Discovery was actually tested, but automatic choice and
future model compliance were not behavior-tested, and no agent/thread/turn was
started for validation. There was no hardware, synthesis or product-test run.

Official documentation checked on 2026-10-19:

- [Build skills](https://learn.chatgpt.com/docs/build-skills): local scan boundaries, linked skill folders, implicit/explicit selection.
- [Codex App Server](https://learn.chatgpt.com/docs/app-server): initialization and read-only `skills/list`.

The installed built-in skill-creator and its `openai_yaml.md` were read in full.
No existing local project skill needed replacing. Built-in creator validation
was reused; `skill-installer` was not needed for a newly authored repo-local
skill rather than a curated/GitHub user-global installation.

## Daily Examples

1. `$mes50hp-development 仅修复 wr_cmd_trans 末拍完成条件，先列验收，再做同路径回归；不改 rd_buf。`
2. `$mes50hp-development 新波形与原判断不一致，请更新假设和计划，选一个能区分原因的最小检查。`
3. `$mes50hp-development 只解释当前彩色信号为何不算干净主图，指出连接证据，不改代码。`
