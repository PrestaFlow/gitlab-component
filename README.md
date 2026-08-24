# PrestaFlow — GitLab CI/CD Component

Run [PrestaFlow](https://prestaflow.io) tests inside GitLab CI: optionally boot a
PrestaShop instance with [Flashlight](https://github.com/PrestaShop/prestashop-flashlight),
execute your PrestaFlow test suites, upload the report (with error and visual-regression
screenshots), and comment the run summary on the merge request.

This is a straight port of the [PrestaFlow GitHub Action](https://github.com/PrestaFlow/github-action) —
same inputs, same upload endpoint (`POST /ci/github-action`, which is provider-agnostic
on the backend), same MR/PR comment format.

---

## Installation

The component lives on GitHub (`PrestaFlow/gitlab-component`). GitLab's Catalog
`include: - component:` shorthand only resolves against `$CI_SERVER_FQDN` (typically
`gitlab.com`), so pick one of the two ways to consume it:

### Option A — mirror to gitlab.com (recommended)

Push this repository as a mirror to `gitlab.com/prestaflow/ci`, then in your
`.gitlab-ci.yml`:

```yaml
include:
  - component: gitlab.com/prestaflow/ci/prestaflow@v0.1.0
    inputs:
      token: $PRESTAFLOW_TOKEN
```

Publish the release on GitLab so the ref shows in the CI/CD Catalog listing.

### Option B — consume directly from GitHub

If you do not want to maintain a mirror, `git clone` the component in a
`before_script` and `include:` a local file:

```yaml
default:
  before_script:
    - if [ ! -d .prestaflow-component ]; then
        git clone --depth 1 --branch v0.1.0
          https://github.com/PrestaFlow/gitlab-component.git .prestaflow-component;
      fi

include:
  - local: .prestaflow-component/templates/prestaflow.yml
    inputs:
      token: $PRESTAFLOW_TOKEN
```

Either way, the scripts run **directly from the checked-out component sources**
(`$CI_PROJECT_DIR/.prestaflow-component/scripts/*.sh` in Option B, or the path
resolved by `$CI_COMPONENT_REF_PATH`-style variables in Option A). The template's
`before_script` handles the clone in Option A too — see [Script bundling](#script-bundling)
below.

---

## Full example

```yaml
include:
  - component: gitlab.com/prestaflow/ci/prestaflow@v0.1.0
    inputs:
      token: $PRESTAFLOW_TOKEN
      project_id: pk_01ABCDEF
      flashlight: "true"
      ps_version: "9.0.0"
      suites: "BackOffice,FrontOffice"
      visual: "true"
      mr_comment: "true"

variables:
  # Required for MR comments — CI_JOB_TOKEN cannot post notes.
  GITLAB_TOKEN: $GITLAB_TOKEN
```

`PRESTAFLOW_TOKEN` and `GITLAB_TOKEN` must be defined as **masked** CI/CD
variables in your project settings.

---

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `api_url` | `https://api.prestaflow.io` | PrestaFlow API base URL. |
| `token` | *(required)* | PrestaFlow API token — pass through a masked CI variable. |
| `project_id` | `""` | PrestaFlow project Product Key (`pk_...`). Optional if the token is scoped. |
| `execute` | `"true"` | Run `composer run prestaflow:json:file` before upload. |
| `suites` | `""` | Comma-separated suite list (`BackOffice,FrontOffice`). Empty = all. |
| `flashlight` | `"false"` | Start a PrestaShop Flashlight Docker instance. Requires `docker:dind`. |
| `ps_version` | `"latest"` | Flashlight image tag (`9.0.0`, `8.1.7`, `latest`). Ignored unless `flashlight=true`. |
| `flashlight_mount` | `"auto"` | `auto` \| `root` \| `modules` \| `themes`. Where the workspace is mounted inside PrestaShop. |
| `flashlight_init_scripts` | `""` | Path (absolute or relative to `$CI_PROJECT_DIR`) to a dir of init scripts, mounted at `/tmp/init-scripts` read-only. |
| `mr_comment` | `""` (auto) | Post/update the Merge Request note. Auto-detected: `true` on MR pipelines, `false` otherwise. |
| `upload_artifacts` | `"true"` | Attach `results.json` + screenshots as GitLab artifacts. |
| `visual` | `"true"` | Enable the visual-regression round-trip (download baselines before, upload actual/diff after). |

---

## Required CI/CD variables

| Variable | Required for | Notes |
|----------|--------------|-------|
| `PRESTAFLOW_TOKEN` | Uploading results | Mask it. Passed as `token` input. |
| `GITLAB_TOKEN` | MR comments | Project or personal access token with `api` scope. `CI_JOB_TOKEN` **cannot** post MR notes. |

---

## Outputs (`dotenv`)

The job writes `prestaflow.env` and exposes it via `artifacts:reports:dotenv`, so
any downstream job in the same pipeline can consume the values as environment
variables:

| Variable | Description |
|----------|-------------|
| `PRESTAFLOW_REPORT_ID` | PrestaFlow report ID. |
| `PRESTAFLOW_REPORT_URL` | URL of the report on prestaflow.io. |
| `PRESTAFLOW_PASSED` | Number of passing tests. |
| `PRESTAFLOW_FAILED` | Number of failing tests. |
| `PRESTAFLOW_SKIPPED` | Number of skipped tests. |
| `PRESTAFLOW_TOTAL` | Total number of tests. |
| `PRESTAFLOW_DURATION_MS` | Total execution duration in milliseconds. |
| `PRESTAFLOW_STATUS` | `success` if `failed==0`, else `failure`. |

Example downstream consumption:

```yaml
notify:
  stage: deploy
  needs:
    - job: prestaflow
      artifacts: true
  script:
    - echo "Report at $PRESTAFLOW_REPORT_URL ($PRESTAFLOW_STATUS)"
```

---

## Script bundling

GitLab CI Components ship YAML only — they do **not** copy the component
repository's files into the runner's workspace. To reach `scripts/*.sh` at
runtime, the template's `before_script` clones the component's source into
`$CI_PROJECT_DIR/.prestaflow-component/` (idempotent — skipped if present, as
happens when the consumer already cloned in their own `before_script` per
Option B). The scripts are then invoked as
`bash .prestaflow-component/scripts/<name>.sh`.

The clone URL and ref default to this GitHub repo at `main`; override with the
`component_repo` / `component_ref` inputs if you fork or pin.

---

## Migration / mirroring

To publish this component on gitlab.com's CI/CD Catalog:

```bash
git clone --mirror https://github.com/PrestaFlow/gitlab-component.git
cd gitlab-component.git
git remote add gitlab https://gitlab.com/prestaflow/ci.git
git push --mirror gitlab
```

Then in the gitlab.com project, tag a release (`v0.1.0`, `v0.2.0`, …) and enable
"CI/CD Catalog project" in **Settings → General**. Consumers can then use the
canonical `component:` shorthand.

---

## Behavior differences vs the GitHub Action

The port is behavior-for-behavior with two small platform-imposed changes:

1. **PR comment auth.** The GitHub Action uses the auto-injected `GITHUB_TOKEN`.
   GitLab's `CI_JOB_TOKEN` cannot create merge-request notes, so this component
   requires an explicit `GITLAB_TOKEN` CI variable (documented above).
2. **Outputs.** The GitHub Action sets step outputs via `core.setOutput`. On
   GitLab, outputs are conveyed through a `dotenv` artifact (`prestaflow.env`).
   Downstream jobs consume them by declaring `needs: [{ job: prestaflow, artifacts: true }]`.

Everything else — inputs, Flashlight boot, visual round-trip, results upload,
comment marker format (`<!-- prestaflow-run:<projectKey> -->`) — matches.

---

## License

MIT — see [LICENSE](LICENSE).
