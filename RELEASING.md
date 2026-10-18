# Releasing lithop

This checklist prepares and publishes one immutable gem version. Run every command from the repository root.

## 1. Prepare the version

1. Update `Lithop::VERSION` in `lib/lithop/version.rb`.
2. Add or update the matching version and release date in `CHANGELOG.md`. Keep the changelog concise; add an `Unreleased` section only when subsequent changes need one.
3. Confirm the README installation and usage examples match the release.
4. Manually open the external links in `README.md` and `docs/`; automated tests intentionally validate only local links and anchors.
5. Commit all intended files and verify that `git status --short` is empty.
6. When the local UI changed, run the Chromium and WebKit browser suite with the development-only Node.js 22 toolchain:

```sh
npm install
npx playwright install chromium webkit
npm run test:browser
```

7. Run the non-publishing release check:

```sh
bundle exec rake release:check
```

The check runs the specs, RuboCop, and RBS validation; builds the gem; checks its version, metadata, runtime dependency, and packaged documentation; installs it into a temporary isolated gem directory; and executes the installed `lithop --version` command.

## 2. Prepare publishing services

Confirm the release commit is on the intended release branch, the repository has an `origin` remote, and GitHub CLI authentication is active:

```sh
git branch --show-current
git remote -v
gh auth status
```

Before the first release, confirm that the `lithop` name is available on RubyGems.org. For manual publishing, sign in and enable MFA:

```sh
gem signin
```

For later releases, confirm that the account owns the gem:

```sh
gem owner lithop
```

Alternatively, configure a RubyGems.org trusted publisher for this repository and its exact publishing workflow. Never commit an API key or `~/.gem/credentials`.

## 3. Publish deliberately

`bundle exec rake release` is a publishing command. It creates and pushes the version tag and publishes the gem to RubyGems.org. Run it only after `release:check` passes and the working tree is clean:

```sh
bundle exec rake release
```

After the tag exists on GitHub, create a GitHub Release and attach the exact gem that passed validation. Replace `0.3.0` for later versions:

```sh
gh release create v0.3.0 --verify-tag --generate-notes
```

Finally, install the published version in a clean environment and verify the CLI:

```sh
gem install lithop -v 0.3.0
lithop --version
```
