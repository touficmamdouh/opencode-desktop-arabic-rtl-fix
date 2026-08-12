# opencode-desktop-bidi-fix

Fixes Arabic/English mixed-text direction (RTL/LTR) in the **OpenCode desktop app**:

- Chat messages (user + assistant/markdown) render right-to-left when they start with Arabic.
- The composer starts typing from the right when the input is Arabic.
- Pure-English content stays left-to-right.

No source changes, no rebuilds. It patches one CSS file inside the app's `app.asar` and repacks it. Fully reversible.

## Quick install

```bash
bash <(curl -s https://raw.githubusercontent.com/touficmamdouh/opencode-desktop-bidi-fix/main/bidi-fix.sh)
```

Or clone and run:

```bash
git clone https://github.com/touficmamdouh/opencode-desktop-bidi-fix.git
cd opencode-desktop-bidi-fix
./bidi-fix.sh
```

## Usage

| Command | What it does |
|---|---|
| `./bidi-fix.sh` | Apply the fix (safe to run repeatedly — idempotent) |
| `./bidi-fix.sh --check` | Check whether the fix is applied |
| `./bidi-fix.sh --force` | Remove old rules and re-apply cleanly |
| `./bidi-fix.sh --uninstall` | Restore the original `app.asar` |

## What it patches

Appends to the main stylesheet inside `app.asar`:

```css
[data-component="markdown"] p,[data-component="markdown"] li,/* …h1-h6, blockquote, td, th… */
{unicode-bidi:plaintext;text-align:start}
[data-component="user-message"] [data-slot="user-message-text"]{unicode-bidi:plaintext;text-align:start}
[data-component="prompt-input"] [contenteditable]{unicode-bidi:plaintext;text-align:start}
```

These selectors are the OpenCode desktop UI's own data attributes (verified against the live DOM of the shipped renderer), so the fix is narrow: chat messages + composer only. Code editors and the rest of the UI keep their default direction.

## Requirements

- Node.js + npx (used to extract/repack the `app.asar` via `@electron/asar` — fetched automatically, cached afterwards).
- Write access to the app install dir, or `sudo` (prompted only at the final copy step).
- Works on Linux (`/opt/OpenCode`), macOS (`/Applications/OpenCode.app`), Windows (`%LOCALAPPDATA%\Programs\...`).

## Notes

- **Updates wipe the fix.** The app self-updates from GitHub; after an update re-run `./bidi-fix.sh`.
- A pristine backup of the original `app.asar` is saved to `~/.cache/opencode-desktop-bidi-fix/` on first apply; `--uninstall` restores it.
- Verified against OpenCode desktop 1.18.x on Linux.

## Why

When the OpenCode UI is set to Arabic, mixed Arabic+English lines render LTR with the English word breaking the Arabic flow. `unicode-bidi: plaintext` makes each paragraph pick its direction from its first strong character — the browser-native fix, no JS involved.
