## Releases

Releases publish automatically when a `vX.Y.Z` tag is pushed (`.github/workflows/release.yml`),
gated on the full CI suite.

**One-time setup:** enable 2FA on your hex.pm account, generate a write key
add it as the `HEX_API_KEY` secret under repo Settings → Secrets → Actions.

**Each release:**
1. Update `CHANGELOG.md` (move `Unreleased` → the new version) and bump `@version` in `mix.exs`.
2. Merge to `main` and confirm CI is green.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Verify at https://hex.pm/packages/a2a_sdk and https://hexdocs.pm/a2a_sdk.
