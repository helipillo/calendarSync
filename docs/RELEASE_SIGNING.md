# Signed + Notarized Releases (Phase 2)

This project includes a signed distribution workflow:

- `.github/workflows/macos-release-signed.yml`

It builds, signs, notarizes, staples, and publishes a DMG.

## Required GitHub Secrets

Set these in: `Settings -> Secrets and variables -> Actions`

1. `MACOS_DEVELOPER_ID_P12_BASE64`
   - Base64 of your Developer ID Application `.p12`
2. `MACOS_DEVELOPER_ID_P12_PASSWORD`
   - Password of the `.p12`
3. `KEYCHAIN_PASSWORD`
   - Temporary CI keychain password
4. `APPLE_API_KEY_ID`
   - App Store Connect API key id
5. `APPLE_API_ISSUER_ID`
   - App Store Connect API issuer id
6. `APPLE_API_PRIVATE_KEY_P8`
   - Full contents of `AuthKey_<KEYID>.p8`

## Triggering a signed release

Option A: tag push
```bash
git tag v1.0.0
git push origin v1.0.0
```

Option B: manual trigger from Actions tab (`workflow_dispatch`).

## Output artifact

- `CalendarBridge-<tag>-macos.dmg`
- `SHA256SUMS.txt`

## Notes

- This workflow assumes `Developer ID Application` certificate is valid.
- For first setup, test on a non-production tag like `v0.1.0-rc1`.
