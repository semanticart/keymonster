# Cutting a release

Releases are published by GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)). Push a
version tag and the workflow builds the release `.app`, signs it with the
Developer ID certificate, stamps the tag into the bundle version, packages it
into a DMG with `make dist`, notarizes and staples it with `make notarize`, and
attaches it to a GitHub Release with auto-generated notes:

```sh
make release VERSION=0.2.1
```

That stamps the version into `Resources/Info.plist`, commits it, tags
`v0.2.1`, and pushes — so the tag and bundle version can't drift apart. (The
equivalent by hand is: edit the plist, commit, `git tag vX.Y.Z`,
`git push origin main vX.Y.Z`.) You can also trigger the workflow manually from
the **Actions** tab, passing the tag to cut.

Signing and notarization credentials come from repository secrets (documented at
the top of the workflow file). To notarize locally, store an app-specific
password once with:

```sh
xcrun notarytool store-credentials keymonster-notary \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password"
```

then run `make dist && make notarize`.
