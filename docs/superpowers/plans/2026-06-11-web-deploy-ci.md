# Web Deploy + CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every push to main is gated by analyze+test and auto-deploys the web build to a public URL.

**Architecture:** Two GitHub Actions workflows. `ci.yml` runs analyze + test on every push and PR. `deploy.yml` runs on main pushes only: test, `flutter build web`, publish `build/web` to GitHub Pages via the Pages artifact flow (no gh-pages branch).

**Tech Stack:** GitHub Actions, `subosito/flutter-action@v2`, `actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`.

---

**⚠️ Decision gate (user, before Task 2):** GitHub Pages on a free-plan org
requires a **public** repo. Options:
- **A (default):** make `Taylor-Software/juice` public. Content note: app text
  derives from the Juice PDF (CC BY-NC-SA per upstream) — public repo with
  attribution is consistent with how juice-roll publishes the same content.
- **B:** stay private → deploy to Cloudflare Pages instead (free for private
  repos). If chosen, replace Task 3 with Cloudflare's
  `cloudflare/pages-action` and skip Task 2.

Ask the user; do not flip visibility without an explicit yes.

### Task 1: CI workflow (analyze + test)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 2: Validate locally that the gated commands pass**

Run: `flutter analyze && flutter test`
Expected: `4 issues found` or fewer, all `info` level (analyze exits 0); `All tests passed!`

Note: if `flutter analyze` exits non-zero because of the 4 known infos,
it won't — infos don't fail the exit code. No flags needed.

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: analyze + test on push and PR"
git push
```

- [ ] **Step 4: Verify the run passes**

Run: `gh run watch --repo Taylor-Software/juice --exit-status $(gh run list --repo Taylor-Software/juice --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected: exit 0, job `test` green. If Flutter setup fails on version, pin `flutter-version: 3.32.x` (match `flutter --version` locally) in the `with:` block and re-push.

### Task 2: Make repo public + enable Pages (after user approves option A)

**Files:** none (repo settings)

- [ ] **Step 1: Flip visibility (user-approved)**

```bash
gh repo edit Taylor-Software/juice --visibility public --accept-visibility-change-consequences
```

- [ ] **Step 2: Enable Pages with Actions as the source**

```bash
gh api -X POST repos/Taylor-Software/juice/pages -f build_type=workflow
```

Expected: HTTP 201. If 409 (already exists): `gh api -X PUT repos/Taylor-Software/juice/pages -f build_type=workflow`.

### Task 3: Deploy workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter test
      - run: flutter build web --release --base-href "/juice/"
      - uses: actions/upload-pages-artifact@v3
        with:
          path: build/web

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: deploy web build to GitHub Pages on main"
git push
```

- [ ] **Step 3: Watch the deploy run**

Run: `gh run watch --repo Taylor-Software/juice --exit-status $(gh run list --repo Taylor-Software/juice --workflow deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected: exit 0, both `build` and `deploy` jobs green.

- [ ] **Step 4: Verify the live site**

Run: `curl -sI https://taylor-software.github.io/juice/ | head -1`
Expected: `HTTP/2 200`

Then load it headfully (preview server not needed — public URL): fetch
`https://taylor-software.github.io/juice/` in a browser or
`curl -s https://taylor-software.github.io/juice/ | grep -o '<title>[^<]*'`
Expected: `<title>Juice Oracle` (or the title in `web/index.html`).

### Task 4: README link

**Files:**
- Modify: `README.md` (top section)

- [ ] **Step 1: Add the live URL under the project title**

Add after the README's opening paragraph:

```markdown
**Live app:** https://taylor-software.github.io/juice/
```

- [ ] **Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: link live web app"
git push
```

- [ ] **Step 3: Confirm CI green on the docs push**

Run: `gh run list --repo Taylor-Software/juice --limit 2`
Expected: latest CI + Deploy runs `completed success`.

## Self-review notes

- Roadmap acceptance ("analyze+test gate" + "live URL") covered by Tasks 1–3.
- `--base-href "/juice/"` matches the project-pages path; if the repo is ever
  renamed, the base href must change with it.
- Deploy re-runs tests deliberately: Pages deploys must never outrun a red
  main.
