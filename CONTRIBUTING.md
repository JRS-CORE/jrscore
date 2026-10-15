# Contributing to JRS Core

Thank you for helping. This page explains how to report problems and how to send changes.

## Reporting a bug

1. Read the FAQ on [docs.jrs-core.com](https://docs.jrs-core.com) and search the existing issues.
2. Open a **Bug report** issue and fill in every field: resource name, steps to reproduce, what you expected,
   what happened, and the errors from the F8 console and the server console.
3. One bug per issue.

Questions about setting up your server belong in the [Discord](https://discord.gg/jrscore), not in issues.

## Suggesting a feature

Open a **Feature request** issue. Explain what you want and why it helps server owners or players.

## Sending a pull request

1. Fork the repository and create a branch from `main` (`fix/inventory-weight`, `feat/stable-search`).
2. Keep each pull request to one change. Small pull requests are reviewed faster.
3. Follow the style of the file you are editing (naming, comments, indentation).
4. Every text a player sees must exist in **both** language files (English and Arabic).
5. Test on a running server and say in the pull request what you tested.
6. Do not add new dependencies without discussing it in an issue first.
7. Never commit licence keys, server keys, database passwords or webhooks.

By sending a pull request you agree that your contribution is released under the
[GNU GPL v3](LICENSE), the license of this project.

## Security problems

Do not open a public issue. Follow [SECURITY.md](SECURITY.md).
