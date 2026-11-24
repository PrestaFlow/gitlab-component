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
  - component: gitlab.com/prestaflow/ci/prestaflow@v0.2.0
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
        git clone --depth 1 --branch v0.2.0
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
  - component: gitlab.com/prestaflow/ci/prestaflow@v0.2.0
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
| `ps_version` | `"latest"` | Flashlight image tag (`9.0.0`, `8.2.8-nginx`, `latest`). Ignored unless `flashlight=true`. See [Flashlight](#flashlight) for the version given to the tests. |
| `flashlight_mount` | `"auto"` | `auto` \| `root` \| `modules` \| `themes`. Where the workspace is mounted inside PrestaShop. |
| `flashlight_init_scripts` | `""` | Path (absolute or relative to `$CI_PROJECT_DIR`) to a dir of init scripts, mounted at `/tmp/init-scripts` read-only. |
| `flashlight_install_module` | `"true"` | When `composer.json` has `type: prestashop-module`, install the mounted module in Flashlight once the shop is ready. Set to `"false"` to skip. |
| `mr_comment` | `""` (auto) | Post/update the Merge Request note. Auto-detected: `true` on MR pipelines, `false` otherwise. |
| `upload_artifacts` | `"true"` | Attach `results.json` + screenshots as GitLab artifacts. |
| `visual` | `"true"` | Enable the visual-regression round-trip (download baselines before, upload actual/diff after). |

---

## Flashlight

With `flashlight: "true"`, the job boots `prestashop/prestashop-flashlight:<ps_version>`
and a `mariadb:lts` through `docker:dind`, waits until `/admin-dev/` answers
(PrestaShop really serving, not just the web server), then prepares the shop
and the settings of your tests.

**PrestaShop version.** `prestaflow/php-library` only accepts a bare version
(`1.7.8.11`, `8.2.8`) in `PRESTAFLOW_PS_VERSION`, and stops on anything else.
The image keeps the tag you give, but the version passed to the tests is read
from it: `8.2.8-nginx` gives `8.2.8`, `1.7.8.11-7.4-fpm-alpine-nginx` gives
`1.7.8.11`. For a tag without a version (`latest`, `nightly`…), the component
reads the image's `PS_VERSION` variable (`latest` is 9.2.1 at the time of
writing). When nothing gives the version, `PRESTAFLOW_PS_VERSION` is left to
you, with a warning in the job log.

> `latest` is PrestaShop 9.2, which installs the Hummingbird theme. Set the
> CI/CD variable `PRESTAFLOW_THEME: hummingbird`, or the library looks for
> Classic's markup.

**Accounts.** Since `prestaflow/php-library` 1.9.0 the library no longer
falls back on demo accounts. With Flashlight, the component provides the
image's back-office account (`admin@prestashop.com` / `prestashop`) and the
demo customer of the PrestaShop fixtures (`pub@prestashop.com` /
`123456789`), at the lowest priority.

**`.env.local`.** The library reads its settings from `.env.local`, or from
`.env` when there is no `.env.local`. The component writes one merged
`.env.local`, from the lowest to the highest priority:

1. the Flashlight accounts (`PRESTAFLOW_BO_EMAIL`, `PRESTAFLOW_BO_PASSWD`,
   `PRESTAFLOW_FO_EMAIL`, `PRESTAFLOW_FO_PASSWD`);
2. your repository's `.env.local`, or `.env` when there is none, copied as is;
3. the shop: `PRESTAFLOW_FO_URL`, `PRESTAFLOW_BO_URL` (`…/admin-dev/`) and
   `PRESTAFLOW_PS_VERSION`;
4. the `PRESTAFLOW_*` CI/CD variables of the job (the component's own
   settings and tokens excepted).

Those keys are removed from composer's environment so the library reads
them from the file. A versioned `.env.local` is merged, not overwritten, and
`after_script` puts it back at the end of the job (or removes the generated
file when the repository had none).

**Module.** When `composer.json` has `type: prestashop-module`, the mounted
module is installed with `php bin/console prestashop:module install <name>`
in the container. If an init-script already installed it, PrestaShop upgrades
it instead. A failed install only prints a warning; set
`flashlight_install_module: "false"` to skip it.

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
| `PRESTAFLOW_FO_URL`, `PRESTAFLOW_BO_URL` | Flashlight only: the shop's front and back office. |
| `PRESTAFLOW_PS_VERSION` | Flashlight only: the PrestaShop version given to the tests, when it could be told. |
| `PRESTAFLOW_FLASHLIGHT_TAG` | Flashlight only: the image tag (`ps_version`). |

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
