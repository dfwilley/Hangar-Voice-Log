# Hangar Log (Hangar Voice Log)

A native iPhone app for recording maintenance work on N721NE by voice.

- Tap **New Entry**, tap **Record Voice Note**, and describe the work out loud.
- The recording is converted to text on the phone. Fix any misheard words.
- Add the date, tach and Hobbs times, the type of work, and photos.
- The app writes a **draft logbook entry** you can copy, share or print.
- **Export All as Spreadsheet** creates a CSV file of every entry.

Nothing leaves the phone unless you share or export it.

## How it's built

There's no Mac involved. Each push to `main` runs a GitHub Actions job on
GitHub's free macOS machines. That job:

1. Generates the Xcode project from `project.yml` (XcodeGen).
2. Runs the unit tests on an iPhone simulator.
3. Builds an unsigned `HangarVoiceLog.ipa`.
4. Publishes the file on the [Releases page](../../releases).

Installation on the iPhone uses Sideloadly on Windows. See
[INSTALL.md](INSTALL.md).

## Files

| Path | What it is |
|---|---|
| `project.yml` | Project definition (app settings, permissions, targets) |
| `HangarVoiceLog/` | App source code (SwiftUI) |
| `HangarVoiceLogTests/` | Unit tests for the logbook text and spreadsheet export |
| `.github/workflows/build.yml` | Cloud build |
