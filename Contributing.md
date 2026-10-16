# Contributing to Bagshui

Here’s how you can get involved and help make Bagshui better!

## Bug reports and feature requests

- Report bugs and request features for this fork on this repository's **Issues** tab. Please include your ClassicAPI version (`/script DEFAULT_CHAT_FRAME:AddMessage(tostring(CLASSIC_API_VERSION))`).
- Problems that also happen on Vanilla/Turtle WoW without ClassicAPI may belong [upstream](https://github.com/veechs/Bagshui/issues) instead.

## Code changes

### All changes happen through pull requests

Please follow [Github Flow](https://docs.github.com/en/get-started/using-github/github-flow). TL;DR:

1. Fork the repo and [create a new branch](https://docs.github.com/en/get-started/using-github/github-flow#create-a-branch) from `main`.
   - If you have collaborator access, you don’t need to fork, but you _do_ need to create a new branch.
2. [Make changes](https://docs.github.com/en/get-started/using-github/github-flow#make-changes).
3. Create a [pull request](https://docs.github.com/en/get-started/using-github/github-flow#create-a-pull-request).

### Please try to follow existing coding style

- Indent using tabs, not spaces (I know, I know).
- Comments that explain the _why_ of the code, not just the _what_.
  - Use [LuaCATS-style function comments](https://luals.github.io/wiki/annotations/#tips).
- No semicolons at end of lines.
- Avoid collapsing `if` statements into one-liners.<br><sup><small>Don’t do this: `if true then return end`.</small></sup>
- Split long lines (including conditions and function calls).<br><sup><small>Try not to go too far past column 120.</small></sup>

### License

You agree that your contributions will be under the [MIT License](http://choosealicense.com/licenses/mit/).

