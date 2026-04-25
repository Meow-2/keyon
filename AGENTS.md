# Repository Guidelines

## Project Structure & Module Organization

This repository is currently a minimal project root. Keep new source files in a clear top-level layout as the project grows:

- `src/` for application or library code.
- `tests/` for automated tests that mirror the `src/` structure.
- `docs/` for design notes, usage guides, and contributor-facing documentation.
- `assets/` for static files such as images, templates, sample data, or fixtures.

Avoid placing generated outputs, temporary files, or local environment data in the repository root.

## Build, Test, and Development Commands

No project-specific build system is present yet. When adding one, document the canonical commands here and prefer simple, repeatable entry points. Examples:

- `npm test` or `pytest`: run the full test suite.
- `npm run build` or `python -m build`: create production artifacts.
- `npm run dev` or `python -m <module>`: run the project locally.

If a command requires environment variables, list the required variable names and provide safe example values.

## Coding Style & Naming Conventions

Follow the conventions of the language or framework introduced by the project. Keep formatting automated where possible, and commit formatter or linter configuration with the codebase.

Use descriptive names for files, modules, functions, and tests. Prefer lowercase directory names such as `src/`, `tests/`, and `assets/`. Keep modules focused on one responsibility, and avoid broad utility files unless shared behavior is genuinely reused.

Change only the necessary parts for the task. Prefer reusing existing mature code, libraries, and local patterns before adding new implementations.

Use lower camel case for project code identifiers, for example `appConfig`, `windowManager`, and `activateOrRun`. When borrowing ideas from external projects, adapt the implementation to this repository's naming, structure, language, and comment conventions instead of copying style wholesale.

## Testing Guidelines

Place tests under `tests/` and name them to match the behavior under test, for example `test_parser.py`, `parser.test.ts`, or `ParserTest.cs` depending on the stack. Tests should cover normal behavior, error paths, and edge cases for any public API or user-facing workflow.

Before opening a pull request, run the full test suite and any configured formatter or linter.

## Commit & Pull Request Guidelines

This directory does not currently contain Git history, so no existing commit convention can be inferred. Use concise, imperative commit messages such as `Add parser validation` or `Fix export path handling`.

Pull requests should include a short summary, the reason for the change, test results, and any relevant screenshots or sample output. Link related issues when available. Keep PRs scoped to one feature, fix, or refactor.

## Security & Configuration Tips

Do not commit secrets, credentials, private keys, or machine-specific configuration. Store local settings in ignored files such as `.env.local`, and provide documented examples such as `.env.example` when configuration is required.

## Agent-Specific Instructions

When working in this repository, think through problems in English and answer the user in Chinese unless they request another language. Code comments should also be written in Chinese.

Structure explanations with the McKinsey Pyramid Principle: start with the main conclusion, then provide the key supporting points, followed by necessary details or examples.

Assume the development environment is Windows 11 with PowerShell as the default terminal. WSL2 is also available and fully functional, but prefer PowerShell commands unless Linux tooling is specifically better for the task.

Act as the technical expert for the project. Provide detailed, concrete answers when explaining decisions, implementation options, risks, commands, or verification steps.

Do not invent undocumented or unconfirmed project behavior in repository documents. Write documentation from the actual repository state and explicit user-confirmed requirements; mark unknown items as pending instead of filling them with assumptions.
