# Agent instructions

- Apple owns the Xcode installation; `.xcode-version` records the required version.
- Nix owns Ruby, Bundler, XcodeGen, and just.
- Bundler owns Fastlane through `Gemfile.lock`.
- Enter the environment with `nix develop` when direnv is unavailable.
- Use `just bootstrap`, `just generate`, `just test`, and `just check`.
- Run release commands through `just deploy`; never expose resolved secrets.
