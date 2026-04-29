---
name: harbor-adapter
description:
  Use this skill when the user says "build a harbor adapter", "adapt this benchmark for
  harbor", "harbor adapter for X", "port this benchmark to harbor", or wants to integrate
  any benchmark dataset into the Harbor evaluation framework
  (https://harborframework.com).
model: sonnet
effort: high
allowed-tools:
  - Bash
  - Read
  - Glob
  - Write
  - Edit
---

# harbor-adapter

Guide an agent through building a Harbor adapter for any benchmark dataset. Produces a
compliant adapter, passes oracle verification, and completes parity experiments before
submitting for review.

## Workflow

### 1. Understand the benchmark

Read all available source material for the benchmark (paper, repo README, dataset files,
leaderboard page). Identify:

- Task format: what constitutes one task (instruction, context, expected answer)
- Environments: what tools or execution context each task requires
- Test/oracle: how correctness is measured (exact match, code execution, LLM judge, etc.)
- Solution format: what a correct agent response looks like

Do not proceed until you can answer: "Given task N, what does a correct solution look like
and how is it scored?"

### 2. Scaffold the adapter

Fork the harbor repo and create a feature branch named `{adapter-name}-adapter`:

```bash
git clone https://github.com/harbor-bench/harbor.git
cd harbor
git checkout -b {adapter-name}-adapter
harbor adapter init {adapter-name}
```

`harbor adapter init` creates `adapters/{adapter-name}/` with stub files. Inspect the
generated structure before writing any code:

```bash
ls adapters/{adapter-name}/
```

### 3. Implement the adapter

Write two files: `adapter.py` and `main.py`.

**`adapter.py`** — parses source benchmark data into Harbor task directories:

- One subdirectory per task under `datasets/{adapter-name}/`
- Each task dir must contain `task.toml` and `instruction.md`
- `task.toml` schema version is always `version = "1.0"` — never change this value
- `task.toml` must have a `name` field: lowercase, hyphens only (sanitize from source)
- Instruction text goes in `instruction.md` — never inline it in `task.toml`
- If the benchmark ships a verifier: copy or reference it in `tests/test.sh`
- `tests/test.sh` must write a float reward (0.0–1.0) to `/logs/verifier/reward.txt`

**`main.py`** — CLI entry point with these flags:

- `--output-dir` — where to write task directories (required)
- `--limit N` — process only the first N tasks (optional)
- `--overwrite` — re-generate existing task dirs (optional, default: skip)
- `--task-ids ID [ID ...]` — process specific task IDs only (optional)

For Reward Kit verifiers, use this pattern in `tests/test.sh`:

```bash
uvx harbor-rewardkit@0.1 /tests
```

### 4. Verify oracle

Run the oracle against all tasks. It must achieve 100% reward before any parity runs:

```bash
harbor run -c adapters/{adapter-name}/run_{adapter-name}.yaml
```

If any tasks fail: debug the verifier or task format. Do not proceed to parity until the
oracle hits 100%.

Open a WIP PR on the harbor repo. Title: `[WIP] {AdapterName} adapter`. Attach a
screenshot of the 100% oracle result in the PR description.

### 5. Plan parity

Contact the Harbor team on Discord **before** starting parity runs. Agree on:

- Which agents to test (e.g. `claude-3-7-sonnet`, `gpt-4o`)
- Which models to use per agent
- Run count per side (minimum 2, prefer 3+)

Do not start `harbor run` parity commands until the team confirms the plan. Record the
agreed plan in a `parity_plan.md` in `adapters/{adapter-name}/`.

### 6. Run parity

Execute parity runs using the agreed agents and models:

```bash
harbor run -p datasets/{adapter-name} -a {agent} -m {model}
```

Run each configuration the agreed number of times. Collect all reward scores.

Compute and report results as **mean ± sample SEM** (not std). The overlap criterion for
parity is:

```
max(harbor_runs) >= min(original_runs)  AND  max(original_runs) >= min(harbor_runs)
```

If the criterion is not met: investigate task format differences, verifier strictness, or
instruction wording before reporting failure.

### 7. Record parity results

Write `parity_experiment.json` in `adapters/{adapter-name}/`:

```json
{
  "adapter_name": "{adapter-name}",
  "agent": "{agent}",
  "model": "{model}",
  "date": "YYYY-MM-DD",
  "metrics": [
    {
      "original": 0.72,
      "harbor": 0.70,
      "original_runs": 3,
      "harbor_runs": 3
    }
  ]
}
```

If multiple agent/model configurations were tested, add one entry per configuration to
the `metrics` array.

### 8. Register the dataset

Initialize and publish the dataset to harbor-datasets:

```bash
harbor init
```

Fill in `dataset.toml`. Key rules:

- Do NOT add a `version` key to `dataset.toml` to control publish version — request
  version tags in the PR description instead
- Ensure `name`, `description`, `source_url`, and `license` fields are present

Submit a PR to the harbor-datasets repo. Verify the dataset resolves correctly:

```bash
harbor run -d {org}/{adapter-name}
```

### 9. Document and submit

Complete all documentation before marking the PR ready:

1. Fill in `adapters/{adapter-name}/README.md`:
   - Benchmark description and citation
   - Task format explanation
   - Verifier description
   - Parity results summary table
   - Usage example

2. Write `adapter_metadata.json` in `adapters/{adapter-name}/`:
   - `adapter_name`, `benchmark_name`, `source_url`
   - `task_count`, `license`
   - `parity_status`: `"pass"` or `"fail"`

3. Change the PR title from `[WIP]` to `[Ready for Review]`.

## Key Rules

- `version = "1.0"` in `task.toml` is the schema version — never change it.
- Do NOT add `version` to `dataset.toml` — request tags in the PR description.
- Oracle must hit 100% reward before any parity runs begin.
- Parity requires at minimum 2 runs per side (3+ preferred).
- Report parity as mean ± sample SEM — never std.
- Instruction text belongs in `instruction.md`, never inlined in `task.toml`.
- `tests/test.sh` writes a float to `/logs/verifier/reward.txt` — this is mandatory.
- Contact the Harbor team on Discord and get plan approval before parity runs.
