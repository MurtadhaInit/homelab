# Agent Guide

## Overview and purpose of this homelab

- Architecture and "how the whole thing fits together" live in [README.md](./README.md).
- Major technical decisions over time live in [docs/decisions.md](./docs/decisions.md).
- This is both a production homelab whose services are critical at home (avoid disruption/downtime if possible) and a learning, experimentation, and career-development environment. For this reason:
  - Prefer **industry-standard patterns** over simpler all-in-one alternatives that hide the
    seams, even if they seem over-engineered (consider the learning value as a decision factor). When a niche option genuinely is the better fit, say so, but note what the standard tool would look like here.
  - Explain the *why*, not just the *what*.
  - Certain exercises that build fluency and relevant expertise can have value on their own, even
    when nothing is broken. Suggest and consider them if appropriate.

## Working agreements

- Don't `git add` or `git commit` unless explicitly told to: make the changes, then hand over
  a succinct commit message plus the exact list of files that belong in that commit.
- If you're going to run ad-hoc commands (e.g. `kubectl apply`) on the cluster which will result
  in state changes, let me know so I'm aware those changes are not git tracked (bypassing GitOps).
- Clean up your own artifacts: e.g. a `result` symlink from a manual `nix build` or a scratch
  file from a verification run.
- When adding a new service or incorporating a new tool or dependency, check for and add the latest
  stable version unless there is a reason not to.
- Verify option names before writing them: e.g. for Helm chart values, NixOS options, Terraform
  variables, Ansible module args, always check the schema or docs rather than guessing a
  plausible key.

## Debugging

- Separate **observed** (what a command literally printed), **inferred** (what that narrows
  it to), and **hypothesis** (a candidate cause, paired with the test that settles it).
  Structure the write-up so the reader can tell which is which without rereading.
- If a hypothesis is testable in under a minute — one command, a file existence check, a
  log grep — *run the test instead of declaring the cause.*
- Do the actual investigative work: read the config, check upstream issues, walk the
  dependency chain. Restating an error message with a generic "try upgrading" is not a
  diagnosis.
- Fix the constraint, don't route around it. Lead with the root-cause fix and present
  the workaround as the fallback.
