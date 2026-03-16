# Releasing LDMS

## Versioning

LDMS follows semantic versioning:
- `MAJOR`: breaking API/runtime changes
- `MINOR`: backward-compatible features
- `PATCH`: backward-compatible fixes

## Release checklist

1. Ensure CI is green.
2. Run local verification:
   - `bundle exec rake test`
   - `bundle exec rake smoke`
   - `bundle exec rake docker_smoke`
3. Update `CHANGELOG.md`.
4. Tag release (`vX.Y.Z`).
5. Publish release notes.

## Release notes template

Use this section structure:

```markdown
## Summary
- ...

## Highlights
- ...

## Breaking changes
- None / ...

## Security
- ...

## Upgrade notes
- ...
```
