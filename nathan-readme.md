# My Readme

## Action Items

- After clone to local, switch the default repo to my fork: `gh repo set-default nathan-ca/quickmd`

## Copy Distribution

1. Simplest: just build it on the other Mac too. Clone the repo there, open in Xcode, let it sign with that Mac's own
   personal-team certificate.
2. Copy it anyway, and manually clear the block. On the receiving Mac: `xattr -cr /path/to/QuickMD.app`
   This strips any quarantine attribute (relevant if the transfer method set one — AirDrop does, a USB drive usually
   doesn't). Then try opening it; if Gatekeeper still blocks it, go to System Settings → Privacy & Security,
   scroll down, and there should be an "Open Anyway" button after the first blocked attempt. One-time approval per Mac,
   no rebuild needed.

## Work Log

2026-07-24

- Update code and have a clean built binary
- Add features:
  - add tree view of working folder, support multiple working folders.
  - persist window location and size
- remain UX issue:
  - the transition of open dialog to previous opened file and window
