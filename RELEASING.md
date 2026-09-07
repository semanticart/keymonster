# Cutting a release

Releases are published by GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)). Push a
version tag and the workflow builds the release `.app`, signs it with the
Developer ID certificate, stamps the tag into the bundle version, packages it
into a DMG with `make dist`, notarizes and staples it with `make notarize`,
writes the Sparkle appcast with `make appcast`, and attaches all of it to a
GitHub Release with auto-generated notes. Installed copies then update
themselves from that release through Sparkle:

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

## Sparkle signing key

Sparkle only installs an update whose appcast entry is signed by the private
EdDSA key matching `SUPublicEDKey` in `Resources/Info.plist`. The private key
lives in the login keychain of the machine it was generated on (Sparkle's
`generate_keys` put it there) and in the `SPARKLE_PRIVATE_KEY` repository
secret, which the workflow pipes into `generate_appcast` on stdin.

Keep a copy somewhere safe: if the key is lost, a new one can be generated, but
every installed copy still trusts the old public key and would have to be
updated by hand once. To export it from the keychain, or import it on another
machine:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key
.build/artifacts/sparkle/Sparkle/bin/generate_keys -f sparkle-private-key
```

To write the appcast locally (after `make dist`), which reads the key from the
keychain:

```sh
make appcast
```
