# substrate.config.md — dokuwiki-canonical-test

Canonical brownfield test target. Per `standards/canonical-test-repos.md` (in canonical's repo).

## Configuration
gating: orchestrator-gated
execution_mode: sequential

## Purpose
This repo exists for canonical to validate substrate changes against a brownfield PHP/flat-file codebase. It is NOT a product. Forked from `dokuwiki/dokuwiki` 2026-05-12 per canonical#642.

## Phases
phases: [test-ground]

## Iteration planning
iterations: none (no product roadmap)
