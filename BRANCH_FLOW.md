# Aqua Branch Flow

## Branches

- `dev`: day-to-day development branch
- `main`: stable release branch

## Recommended flow

1. Do active work on `dev`.
2. Open a pull request from `dev` into `main` when you want to ship.
3. Merge that PR into `main`.
4. Tag the release from `main` with `v<version>` such as `v0.0.2`.
5. GitHub Actions will validate and publish the release from `main`.

## Local helpers

- Create/upload a release build:
  - `./aqua-release`
- Open a release PR from `dev` to `main`:
  - `./aqua-release-pr`

## Notes

- CI runs on pushes to both `dev` and `main`, plus PRs targeting either branch.
- The release workflow now refuses to publish unless the tagged commit is already on `main`.
- `gh auth login -h github.com` must be set up before using `./aqua-release-pr`.
