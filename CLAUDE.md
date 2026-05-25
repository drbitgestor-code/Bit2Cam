# gstack

## Setup (run once per machine)

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup
```

If `bun` is not installed, install it first:

```bash
BUN_VERSION="1.3.10" && tmpfile=$(mktemp) && curl -fsSL "https://bun.sh/install" -o "$tmpfile" && BUN_VERSION="$BUN_VERSION" bash "$tmpfile" && rm "$tmpfile"
```

## Usage

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

Available gstack skills:
- `/office-hours` — async Q&A and advice
- `/plan-ceo-review` — CEO-level plan review
- `/plan-eng-review` — engineering plan review
- `/plan-design-review` — design plan review
- `/design-consultation` — design consultation
- `/design-shotgun` — rapid design exploration
- `/design-html` — generate HTML designs
- `/review` — code review
- `/ship` — ship a change
- `/land-and-deploy` — land and deploy
- `/canary` — canary deploy
- `/benchmark` — performance benchmarking
- `/browse` — web browsing (use this for all web browsing)
- `/connect-chrome` — connect to a Chrome instance
- `/qa` — full QA pass
- `/qa-only` — QA without setup
- `/design-review` — design review
- `/setup-browser-cookies` — set up browser cookies
- `/setup-deploy` — set up deployment
- `/setup-gbrain` — set up gbrain
- `/retro` — retrospective
- `/investigate` — investigate an issue
- `/document-release` — document a release
- `/document-generate` — generate documentation
- `/codex` — codex tasks
- `/cso` — CSO tasks
- `/autoplan` — auto-generate a plan
- `/plan-devex-review` — devex plan review
- `/devex-review` — developer experience review
- `/careful` — careful/cautious mode
- `/freeze` — freeze changes
- `/guard` — guard mode
- `/unfreeze` — unfreeze changes
- `/gstack-upgrade` — upgrade gstack
- `/learn` — learning mode
