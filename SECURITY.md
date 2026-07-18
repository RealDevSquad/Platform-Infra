# Security Policy

## Scope

This repository defines the Real Dev Squad **services box**: its AWS layer
(OpenTofu), container definitions (Docker Compose + Caddy), and provisioning
scripts. Vulnerabilities in the *services themselves* (todo, skilltree,
tiny-site, discord) belong in their own repositories — this policy covers the
infrastructure definitions and tooling here.

There is no version support matrix: this is continuously deployed
infrastructure with a single line of development. Fixes land on `main`.

## Reporting a vulnerability

**Please do not open a public issue for security problems.** Use GitHub's
private vulnerability reporting on this repository (Security → "Report a
vulnerability"), or contact the Real Dev Squad maintainers directly. You can
expect an acknowledgement within a few days; whether accepted or declined,
you'll get a reasoned answer.

## Secrets and identifiers

By design, this repo contains **no credentials, no account identifiers, and no
private resource IDs** — real values live outside the repository, and an
automated guard (pre-commit scan + publishing gate) enforces it. If you spot
something that looks like a leaked secret or identifier anyway, report it
privately as above rather than referencing it in a public issue — the
maintainers will rotate and purge it.
