# F-Droid

Submitted 2026-11-12: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/57028

## Model

- fdroiddata has no `flutter` srclib → Flutter SDK is vendored as a git
  submodule (`submodules/flutter`) in this repo, mirroring LocalSend's
  metadata recipe. The bot copies the recipe for every future release tag.
- Metadata lives in the fdroiddata clone (`~/dev/fdroiddata/metadata/
  io.github.kurobeats.sloth.yml`); never commit or edit it here.
- After merge, releases are fully automatic: bump pubspec `version`,
  tag `vX`, push. No fdroiddata changes needed.

## Automator

`tool/fdroid.py check|prepare|metadata|submit` — `tool/` is gitignored.
GitLab project access tokens only via `$GITLAB_TOKEN` env var
(`https://git:<token>@gitlab.com/...` for git over https). Never commit,
log, or store tokens in files.

## Guards

- `.github/workflows/build.yml` fails any `v*` release tag that lacks the
  `submodules/flutter` gitlink (a submodule-less tag breaks F-Droid buildbot).
- GitLab forks of fdroiddata can wedge with `empty_repo: true` for hours —
  delete and re-fork; the new fork gets a new project id and a new token.
