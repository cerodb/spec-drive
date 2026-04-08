---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Tasks

- [x] decide the strategic direction for installation/distribution
- [x] preserve the older `P283` spec materials under `spec/legacy-spec/`
- [x] open a new canonical spec-drive track in `spec/`
- [x] define the minimal structure of `cerodb/cerodb-plugins`
- [ ] decide how `spec-drive` should be represented inside the marketplace repo
- [ ] decide whether `think-tank` should be migrated into the same marketplace in the same wave or later
- [x] decide that the initial marketplace wave includes both:
  - `spec-drive`
  - `think-tank`
- [x] harden `README.md` and `INSTALL.md` so they reflect the marketplace direction honestly during the transition
- [x] define a temporary transition note for users until the marketplace repo is live
- [x] scaffold the marketplace repo locally with `spec-drive` as the first plugin
- [x] extend the local scaffold to include `think-tank`
- [ ] sanitize `spec/legacy-spec/` before ever publishing it from this repo
- [ ] turn the local `cerodb-plugins` scaffold into the canonical GitHub marketplace repo
- [ ] register `spec-drive` in the marketplace and validate discovery
- [ ] register `think-tank` in the marketplace and validate discovery
- [ ] validate install from the marketplace in a fresh Claude-compatible environment
