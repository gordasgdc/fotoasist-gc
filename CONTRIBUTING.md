# Contributing to FotoAsist GC

Thank you for wanting to help. This project is open to contributions and is maintained occasionally by one person, in spare time. Please read this page first; it keeps everyone's effort useful.

## What to expect

- Issues and pull requests are read, but not on a schedule. A reply can take weeks.
- There is no roadmap commitment and no support obligation. Small, focused, tested pull requests are the most likely to be merged.
- For a larger change, open an issue first and describe what you want to do, so you do not spend time on something that cannot be merged.

## Reporting a problem

Open an issue with: the FotoAsist GC version and build (menu FotoAsist GC → About → "Copy version information"), the macOS version, the camera model if a RAW file is involved, what you did, what you expected and what happened.

Do not attach private photographs. If a file is needed to reproduce the problem, attach one you are allowed to publish. The diagnostic package the application can export is redacted, but look at it before you attach it.

Security problems: see [SECURITY.md](SECURITY.md).

## Pull requests

1. Fork, create a branch, make the change.
2. Run `scripts/swift.sh test`. All tests must pass. Add or update tests for what you changed; tests use synthetic data they generate themselves.
3. Keep the change focused. Do not reformat code you are not changing.
4. Describe in the pull request what changes for the user and how you checked it.

Rules that are checked in review:

- **No photographs, RAW files, keys, certificates, tokens or personal data** in the repository, in tests or in fixtures.
- **Originals are read-only.** Nothing may write to a user's original file or next to it.
- **No network calls** other than the existing update check. The application does not upload anything.
- **Image mathematics**: say which domain a step works in (scene-linear, log code, display), keep neutral settings an exact identity, and add a numeric test. Mark approximations as approximations.
- **Interface texts**: the source text is Romanian; add the English and Spanish translations in `core/Sources/PhotoCore/LocalizationTables.swift` (the localisation tests check coverage).
- **Dependencies**: a new dependency needs a licence compatible with GPL-3.0-or-later and an entry in `THIRD_PARTY_NOTICES.md`. Do not copy code whose licence you have not checked.
- **Edition switch**: leave the `GDC_PA_OPEN_EDITION` / `GDC_PC_PREMIUM` blocks in place (see [BUILDING.md](BUILDING.md)).

## Authorship and licence of contributions

- By submitting a contribution you agree that it is licensed under **GPL-3.0-or-later**, the licence of the project, and you confirm that you have the right to submit it.
- So that fixes made here can also reach the full edition of FotoAsist GC, you additionally allow the project author, Dumitru Cristinel Gordas (GDC), to include your contribution in that edition. If you do not want that, say so in the pull request and it will be discussed before merging.
- Commits must be authored by the person who is responsible for them, with a real name or a consistent pseudonym and a working e-mail address. `Co-authored-by` trailers are for people who actually co-wrote the change.
- Do not list tools as authors or co-authors. You are responsible for every line you submit, however it was produced, including its licence.
- Keep existing copyright and licence notices of third-party code and data.

You can add yourself to [AUTHORS.md](AUTHORS.md) in your first merged pull request.

## Conduct

Be respectful and stay on the subject. Discussions that are not about the project, and personal attacks, will be closed.
