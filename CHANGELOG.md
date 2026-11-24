# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-24

Flashlight fixes of the GitHub Action v2.3.0 to v2.4.1, for
`prestaflow/php-library` 1.9.0.

### Fixed
- **`PRESTAFLOW_PS_VERSION` is taken from the image tag, not set to the tag
  itself.** The library only accepts a bare version, so `latest` (the default)
  or `8.2.8-nginx` stopped the run on `Error with version …`. `8.2.8-nginx`
  now gives `8.2.8`. For a tag without a version (`latest`, `nightly`…), the
  version is read from the image's `PS_VERSION` variable, with
  `app/AppKernel.php` as a fallback; when nothing gives it, it is left to you
  with a warning. The image still uses the tag as given.
- **Flashlight accounts.** The generated `.env.local` sets the image's
  back-office account (`admin@prestashop.com` / `prestashop`) and the demo
  customer (`pub@prestashop.com` / `123456789`) at the lowest priority:
  php-library 1.9.0 no longer falls back on demo accounts.
- **A versioned `.env.local` is no longer overwritten.** It is merged into the
  generated one and restored in `after_script`. The generated file is, from
  the lowest to the highest priority: Flashlight accounts, your `.env.local`
  (or `.env`), the shop's `PRESTAFLOW_FO_URL` / `PRESTAFLOW_BO_URL` /
  `PRESTAFLOW_PS_VERSION`, then the job's `PRESTAFLOW_*` CI/CD variables.
  Those keys are removed from composer's environment so the library reads
  them from the file.
- **Readiness.** The job waits for `/admin-dev/` to answer 302/200 instead of
  any 2xx/3xx on `/`, and names the last status on timeout.
- The template installs `docker-cli-compose` on Alpine images: `docker compose`
  is not part of `docker-cli`.

### Added
- `flashlight_install_module` input (default `"true"`): when `composer.json`
  has `type: prestashop-module`, the mounted module is installed with
  `php bin/console prestashop:module install <name>` once the shop is ready.
  A failed install only warns.
- `PRESTAFLOW_BO_URL` and `PRESTAFLOW_FLASHLIGHT_TAG` in `prestaflow.env`.

### Changed
- The template passes `ps_version` to the scripts as `PRESTAFLOW_FLASHLIGHT_TAG`
  (it was `PRESTAFLOW_PS_VERSION`). `PRESTAFLOW_PS_VERSION` in `prestaflow.env`
  is now the bare version, and is absent when it could not be told.
- A `PRESTAFLOW_*` CI/CD variable now reaches the tests with Flashlight, and
  wins over the generated values (e.g. `PRESTAFLOW_THEME: hummingbird` for
  `latest`, which is PrestaShop 9.2).
- **Installation from GitHub with `include: remote`**, pinned to a tag
  (`https://raw.githubusercontent.com/PrestaFlow/gitlab-component/v0.2.0/templates/prestaflow.yml`).
  The README described a gitlab.com mirror (`gitlab.com/prestaflow/ci`) that
  was never published, and an "Option B" (`include: local` of a file cloned in
  `before_script`) that cannot work: includes are resolved when the pipeline
  is created. Mirroring is now an optional section for your own instance.
- The `component_ref` input defaults to the template's own release (`v0.2.0`,
  was `main`), so the cloned scripts match the YAML. The release workflow
  checks it instead of mirroring to gitlab.com.

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
