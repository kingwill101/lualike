# devtools-profiler Pain Points And Improvements

This file records friction found while using the `devtools-profiler` CLI and
MCP flow. It is not a profile result log and should not contain app-specific
optimization findings.

## Region Capture Is Easy To Misuse

Pain: `attach` can profile a live VM service, but it cannot recover explicit
region markers from `devtools_region_profiler`. That distinction is easy to
miss when switching between a live Flutter app and a profiler-launched run.

Impact: an attach run can look successful while silently missing the most useful
per-region breakdown.

Suggestion: when `attach` is used, print a clear pre-capture warning that region
markers are unavailable unless the target process was launched by
`devtools-profiler run`.

## Empty CPU Tables Are Hard To Diagnose

Pain: package filters such as `--include-package lualike` can hide all CPU
frames if local `file://` paths are not mapped to the expected package name.
The profiler can still show memory output, making the capture look partially
valid.

Impact: users waste time investigating the target app when the real problem is
filtering.

Suggestion: detect when CPU samples exist before filtering but no frames remain
after filtering. Print a warning naming the active filters and suggest retrying
without them.

## Artifact Paths Are Ambiguous

Pain: `--artifact-dir` is resolved relative to the shell working directory, not
the target `--cwd`. This is surprising when launching a package-local command
from the monorepo root.

Impact: artifacts can be written somewhere different than expected, making
follow-up `summarize`, `inspect`, and `compare` commands awkward.

Suggestion: always print the fully resolved artifact directory in both JSON and
human-readable output.

## Summarize Has Too Much Shape Sensitivity

Pain: sometimes the natural input is the artifact directory, and sometimes it is
`overall/summary.json`. Users should not need to remember which command accepts
which form.

Impact: summaries take extra trial and error, especially when iterating quickly
between captures.

Suggestion: make `summarize`, `explain`, `inspect`, `search-methods`, and
`compare` accept either a session directory or a summary/profile artifact where
that is technically possible.

## Memory Output Needs First-Class Deltas

Pain: memory is often the reason for profiling lualike, but the most
actionable class-level deltas are not always surfaced prominently in standard
summaries.

Impact: users are pushed toward JSON inspection or external tools even when the
CLI should be enough.

Suggestion: add a default "top memory classes by delta" section to
`summarize`, including live bytes, live instances, new instances, and retained
heap delta when available.

## CLI Should Avoid Requiring `jq`

Pain: JSON output is useful, but normal investigation should not require `jq` to
answer basic questions such as "what retained the most memory?" or "which method
is hottest?".

Impact: profiling becomes slower and less portable across terminals.

Suggestion: keep the CLI text output complete enough for standard investigation:
top CPU self/total methods, top memory classes, region table, warnings, artifact
paths, and the VM service URI.

## Duration Defaults Are Easy To Get Wrong

Pain: short captures are useful for live UI profiling, but too short for
startup, Flutter compilation, or full memory scenario groups. Long captures are
too slow for tight interaction windows.

Impact: users either capture nothing useful or wait longer than necessary.

Suggestion: add scenario-aware guidance in the CLI output. Examples:

- warn when a profiler-launched Flutter command is still compiling
- suggest longer durations when no samples were captured
- print elapsed startup time separately from measured profiling time

## Run Command Echo Should Be Complete

Pain: after a run finishes, it is not always obvious which exact target command,
working directory, VM service URI, filters, and capture kinds produced the
artifact.

Impact: runs are harder to compare and harder to reproduce.

Suggestion: include a "reproduction block" in non-JSON summaries with:

- profiler command
- target command after `--`
- resolved target `--cwd`
- VM service URI
- capture duration
- artifact directory
- active filters

## MCP And CLI Parity Should Be Explicit

Pain: it is not always clear whether the MCP tools expose the same options and
views as the CLI commands.

Impact: users switch between MCP and CLI without knowing which one is better for
`attach`, method inspection, region summaries, or comparison.

Suggestion: document and expose parity intentionally:

- `profile_run`
- `profile_attach`
- `profile_summarize`
- `profile_explain_hotspots`
- `profile_search_methods`
- `profile_inspect_method`
- `profile_compare`

Each MCP response should include the matching CLI command that would reproduce
the same result.
