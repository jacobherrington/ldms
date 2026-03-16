# Contributing to LDMS

Thanks for helping improve LDMS.

## Quick setup for new contributors

Start with:

- `docs/QUICK_SETUP.md`

## Development setup

Recommended runtime for contributors:

1. Install Ruby 3.2+ and Bundler.
2. Install Ollama and pull the embed model:
   - `ollama pull nomic-embed-text`
3. Install dependencies:
   - `bundle install`
4. Verify local setup:
   - `bundle exec rake doctor`
   - `bundle exec rake smoke`

Container runtime is also supported:
- `bundle exec rake bootstrap`

## Running tests

- `bundle exec rake test`

Please add tests for new logic and bug fixes.

## Pull request expectations

- Keep changes focused and small.
- Add/adjust docs for behavior changes.
- Include tests for normal path + relevant edge cases.
- Keep sensitive material out of test fixtures and memory records.

## Commit style

Use concise imperative commits that explain intent, for example:
- `add docker bootstrap flow`
- `harden secret redaction in memory service`

## Reporting issues

Use issue templates for bug reports and feature requests.
For security vulnerabilities, follow `SECURITY.md` instead of opening a public issue.
