# Contributing Guidelines

Thank you for your interest in contributing to our project. Whether it's a bug report, new feature, correction, or additional
documentation, we greatly value feedback and contributions from our community.

Please read through this document before submitting any issues or pull requests to ensure we have all the necessary
information to effectively respond to your bug report or contribution.


## Reporting Bugs/Feature Requests

We welcome you to use the GitHub issue tracker to report bugs or suggest features.

When filing an issue, please check existing open, or recently closed, issues to make sure somebody else hasn't already
reported the issue. Please try to include as much information as you can. Details like these are incredibly useful:

* A reproducible test case or series of steps
* The version of our code being used
* Any modifications you've made relevant to the bug
* Anything unusual about your environment or deployment


## Repository Layout and Translation Policy

This repository keeps its documentation in two trees:

| Tree | Role | Editing |
|------|------|---------|
| `ja/` | **Source of truth** (Japanese) | Edit here |
| `en/` and the root `README.md` | Generated artifacts (English) | Do not edit directly |
| `install.sh`, `VERSION`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Language-independent | Kept in English |

`en/` is generated from `ja/` and committed to the repository (treated like a lockfile),
so that `install.sh --lang en` works immediately after cloning. The sync state is
recorded in `tools/i18n.lock` and enforced by `tools/check-i18n.sh`, which fails both
when `ja/` has changed without the translation being redone and when a generated file
has been edited directly.

**Because `en/` is generated, a pull request that only changes `en/` cannot be merged
as-is.** Please contribute in one of these ways:

* Open an **issue** describing the problem or proposal (preferred for wording,
  factual errors, and unclear explanations).
* Open a **pull request against `en/`** — it is accepted as a *content proposal*. A
  maintainer reflects the change into `ja/` and regenerates `en/`. Your PR may
  therefore be closed with a reference to the commit that carries the change.

Keeping the translation in sync is the maintainers' responsibility. **You are not
expected to update the translation** in your contribution.

Identifiers used as cross-language anchors — `CP-N`, `DP-N`, `HOLD-N`, `LL-N`, `ADR-N`,
`Tier`, `Phase`, `Step`, `Mode A`-`C` — are never translated and never renumbered
casually; they are referenced from both trees and from installed user projects.
Terminology is fixed in `tools/glossary.tsv`.


## Contributing via Pull Requests
Contributions via pull requests are much appreciated. Before sending us a pull request, please ensure that:

1. You are working against the latest source on the *main* branch.
2. You check existing open, and recently merged, pull requests to make sure someone else hasn't addressed the problem already.
3. You open an issue to discuss any significant work - we would hate for your time to be wasted.
4. If your change touches documentation, you changed `ja/` (not `en/`) — see
   "Repository Layout and Translation Policy" above.
5. `tools/check-i18n.sh` passes, and all shell scripts pass `bash -n`.

To send us a pull request, please:

1. Fork the repository.
2. Modify the source; please focus on the specific change you are contributing. If you also reformat all the code, it will be hard for us to focus on your change.
3. Ensure local tests pass.
4. Commit to your fork using clear commit messages.
5. Send us a pull request, answering any default questions in the pull request interface.
6. Pay attention to any automated CI failures reported in the pull request, and stay involved in the conversation.

GitHub provides additional document on [forking a repository](https://help.github.com/articles/fork-a-repo/) and
[creating a pull request](https://help.github.com/articles/creating-a-pull-request/).


## Finding contributions to work on
Looking at the existing issues is a great way to find something to contribute on. As our projects, by default, use the default GitHub issue labels (enhancement/bug/duplicate/help wanted/invalid/question/wontfix), looking at any 'help wanted' issues is a great place to start.


## Code of Conduct
This project has adopted the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct).
For more information see the [Code of Conduct FAQ](https://aws.github.io/code-of-conduct-faq) or contact
opensource-codeofconduct@amazon.com with any additional questions or comments.


## Security issue notifications
If you discover a potential security issue in this project we ask that you notify AWS/Amazon Security via our [vulnerability reporting page](http://aws.amazon.com/security/vulnerability-reporting/). Please do **not** create a public github issue.


## Licensing

See the [LICENSE](LICENSE) file for our project's licensing. We will ask you to confirm the licensing of your contribution.
