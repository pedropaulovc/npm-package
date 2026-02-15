# PACKAGE_NAME

## Project Structure

```
index.d.ts                      # All type definitions (the package payload)
test/smoke.test.ts              # Smoke test
package.json                    # types field, no main/module
tsconfig.json                   # Strict TS config for validation
CHANGELOG.md                    # Keep a Changelog format
.github/workflows/publish.yml  # CI: test -> release -> publish
```

## Commands

- `npm run typecheck` — Validate `index.d.ts` compiles under strict mode
- `npm test` — Run smoke tests

## Publishing a New Version

The publish workflow runs on `v*` tag push. It runs typecheck + tests, creates
a GitHub Release from the CHANGELOG entry, and publishes to npm with provenance.

### Steps

1. Make your changes to `index.d.ts`
2. Run `npm run typecheck` and `npm test` locally
3. Add a `## [x.y.z] - YYYY-MM-DD` section to `CHANGELOG.md` (above `[Unreleased]` contents, then clear Unreleased)
4. Update the comparison links at the bottom of `CHANGELOG.md`
5. Bump version: `npm version patch|minor|major` (updates package.json + creates git tag)
6. Push: `git push --follow-tags`
7. The workflow will: verify version match -> extract changelog -> create GitHub Release -> publish to npm

### Version Semantics

- **Patch**: JSDoc improvements, adding optional fields, fixing comments
- **Minor**: New types, new union members
- **Major**: Removing or renaming exported types, changing required fields

### If the Workflow Fails

- **Version mismatch**: `package.json` version must match the tag (e.g. tag `v0.2.0` -> version `"0.2.0"`)
- **Missing changelog**: Add a `## [x.y.z]` section to `CHANGELOG.md` for the version being released
- **npm auth**: Uses trusted publishing (OIDC). `NPM_TOKEN` is auto-injected into the `npm` GitHub environment -- no manual secret setup needed

## Setup After Creating From Template

1. Replace all `PACKAGE_NAME` occurrences with your actual package name
2. Update `CHANGELOG.md` date and links
3. Configure npm trusted publishing for the new package
4. Create an `npm` environment in the GitHub repo (auto-created by trusted publishing)
5. Create a tag ruleset to make `v*` tags immutable (block update + deletion)
