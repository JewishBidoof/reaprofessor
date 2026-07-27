# Publishing on ReaPack

ReaProfessor is packaged for [ReaPack](https://reapack.com/).

## Import URL (after index is published on main)

```
https://github.com/JewishBidoof/reaprofessor/raw/main/index.xml
```

In REAPER: **Extensions → ReaPack → Import a repository…** → paste URL → OK → Synchronize packages.

## Package layout

| Path | Role |
| --- | --- |
| `Live/ReaProfessor.lua` | Metapackage entry scanned by `reapack-index` |
| `scripts/ReaProfessor/*.lua` | Scripts registered in the Action List (`[main]`) |
| `scripts/ReaProfessor/lib/*.lua` | Libraries (`[nomain]`) |
| `resources/osc/ReaProfessor.ReaperOSC` | Optional OSC pattern data |

## Local check

```bash
gem install reapack-index
reapack-index --check --no-commit .
```

## Release checklist

1. Bump `-- @version` in `Live/ReaProfessor.lua` and script headers (keep in sync).
2. Update `@changelog` / README.
3. Commit on `main` (GitHub Action regenerates `index.xml`).
4. Users synchronize ReaPack to get the new version.

## Optional: ReaTeam

To publish on ReaTeam Scripts instead of a self-hosted index, use the [ReaPack upload form](https://reapack.com/upload/reascript) with the same metadata headers. Prefer the self-hosted index while the package is evolving.
