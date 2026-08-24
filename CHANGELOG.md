# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-24

### Added
- Initial GitLab CI/CD Component port of [PrestaFlow/github-action](https://github.com/PrestaFlow/github-action).
- `templates/prestaflow.yml` component with a full `spec:inputs` mirroring the GitHub Action's inputs.
- `scripts/flashlight.sh` — starts a PrestaShop Flashlight Docker instance (docker-in-docker).
- `scripts/visual-download.sh` — fetches baselines from `/ci/visual/baselines` before the run.
- `scripts/runner.sh` — runs `composer run prestaflow:json:file`.
- `scripts/visual-upload.sh` — no-op; visual artifacts are shipped by `upload.sh` as part of the multipart form.
- `scripts/upload.sh` — POSTs `results.json` + screenshots to `/ci/github-action` with a GitLab `ci` block.
- `scripts/comment-mr.sh` — posts or updates a Merge Request note (requires `GITLAB_TOKEN`).
- `scripts/outputs.sh` — writes `prestaflow.env` for downstream jobs' `dotenv` report.
- `tests/smoke.yml` — offline smoke test with a mocked upload endpoint.
