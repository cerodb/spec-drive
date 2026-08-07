# Spec-Drive v1.4.0

This release adds portable, scoped project registration without breaking legacy layouts.

## Highlights

- project and workspace configuration scopes resolve independently per key
- `/spec-drive:new` delegates to an executable atomic scaffold
- safe deterministic creation with rollback and existing-destination protection
- canonical `spec/`, `audit/`, `input/`, and `output/` project destinations
- compatibility with flat, nested, heterogeneous, and legacy workspace layouts
- stronger runtime validation, concurrency coverage, portability checks, and disclosure scanning

## Validation

- full local suite: 458 assertions passed
- targeted regression gate: 344 assertions passed
- tracked shell syntax and patch-integrity checks passed
- no runtime dependency was added

Source release and marketplace/distribution synchronization are separate actions and require separate owner approval.
