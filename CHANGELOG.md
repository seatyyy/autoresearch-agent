# Changelog

Format: `## <image-tag> — <date>` then a bullet list of what changed for users of this shell repo. Bumps are landed by the contractor; pull this repo to pick them up.

## 0.5 — 2026-05-21

- Initial Dockerized release.
- Stage 1 (scope) is a 3-agent flow: analysis → eval_design → orchestrator, then critic/evolve loop up to 3 iterations or score ≥ 8.
- Stage 2 (literature) uses web_search-only on haiku.
- Stage 3 (experiment) generates `03_experiment/run.py`, executes with timeout + self-heal, emits `analysis.md` + `04_memo.md`.
- Stage 4 (summary) aggregates into `00_summary.md`.

### Prompt template variables introduced this release

- `prompts/scope.md`: `{topic}`, `{seed_papers_section}`, `{iterative_section}`, `{eval_metrics}`, `{analysis}`
- `prompts/analysis.md`: `{topic}`
- `prompts/eval_design.md`: `{topic}`
- `prompts/critic.md`: `{topic}`, `{analysis}`, `{candidate_solutions}`
- `prompts/evolve.md`: `{topic}`, `{analysis}`, `{candidate_solutions}`, `{eval_metrics}`, `{feedbacks}`
