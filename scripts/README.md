# scripts/ — repo-wide tooling

| Script | Purpose |
|---|---|
| `bootstrap.sh` | Provision a fresh Ubuntu arm64 box into the services server (step 2 of `docs/new-box-bootstrap.md`). Idempotent; stops for real env values on first run. **EC2-only gate**: refuses off-EC2 (`BOOTSTRAP_FORCE=1` to override). |
| `validate-stack.sh` | Behavior-only stack validation (routing matrix, wiring, optional authed layer via `*_TOKEN` env vars). Never reads env files; never prints secrets/tokens. Works locally and on a box. |
| `sanitize.sh` | Flip the whole tree between anonymized (`{{PLACEHOLDER}}`) and real-value states. Forward = anonymize (+ YAML-placeholder guard + residue scan that must end "clean."); `--restore` = real values; `--check` = scan only, mutate nothing (what the pre-commit hook runs). Mapping lives outside the repo (`../.infra-private/values.env`). |
| `hooks/pre-commit` | Refuses commits while identifiers/ticket refs are present in committable files. Activate once per clone: `git config core.hooksPath scripts/hooks`. |

`render-env.sh` (the ssm provider) additionally **hard-refuses unless
`docker/.env` declares `ENV_PROVIDER=ssm`** — the mode gate of
`docs/config-model.md`.

Placement rule: tooling that spans the repo lives here; tooling specific to one
area lives with that area (e.g. `tofu-prod-import/generate-tfvars.sh`).
