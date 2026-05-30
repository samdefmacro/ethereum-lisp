# Common Lisp Agent Tooling Evaluation

This note records the first pass at using a live Common Lisp image for agent
development on this repository.

## Tools Checked

- Alive / alive-lsp: VSCode-oriented Common Lisp tooling with LSP, Swank-backed
  REPL integration, inline evaluation, macro expansion, debugger, inspector, and
  jump-to-definition support. It is useful for human IDE work, but it is less
  directly useful to Codex unless we expose the same live-image operations as
  agent-callable tools.
- `hanshuebner/lisp-mcp`: small MCP server that can evaluate Common Lisp in
  the MCP server process, or connect to a running Swank server via
  `SWANK_PORT`. This is closest to the workflow we want because it lets an
  agent talk to the same kind of live image SLIME/Sly uses.
- `quasi/cl-mcp-server`: broader MCP server for a persistent Common Lisp REPL,
  with evaluation, syntax validation, introspection, ASDF, profiling, and error
  reporting tools. It is promising, but currently alpha and brings a larger
  dependency/setup surface.

References:

- https://marketplace.visualstudio.com/items?itemName=rheller.alive
- https://lispcookbook.github.io/cl-cookbook/vscode-alive.html
- https://github.com/hanshuebner/lisp-mcp
- https://github.com/quasi/cl-mcp-server

## Local Trial

Swank and Slynk were installed through Quicklisp for local evaluation. The
repository now has a persistent development image entry point:

```sh
sbcl --load scripts/dev-image.lisp
```

Useful forms inside the image:

```lisp
(run-ethereum-lisp-test "trie-fixture-vectors")
(run-ethereum-lisp-tests)
```

For SLIME/Sly/MCP clients that speak to Swank:

```sh
ETHEREUM_LISP_SWANK_PORT=4005 \
ETHEREUM_LISP_DEV_IMAGE_WAIT=1 \
sbcl --script scripts/dev-image.lisp
```

The script loads all project and test definitions without immediately running
the full suite, then optionally starts a localhost Swank server.

## Measurements

- Cold CLI full suite: `sbcl --script tests/run-tests.lisp` took about 29.5s.
- First load of the dev image plus full suite took about 29.5s.
- Re-running the full suite in the same image took about 26.2s.
- Re-running `trie-fixture-vectors` in the same image took about 0.2s.

## Assessment

The live-image route is worth keeping, but not as a replacement for the CLI
test suite.

Benefits:

- Very fast targeted test loops once the image is warm.
- Direct introspection of packages, symbols, macroexpansions, function
  redefinitions, and live data structures.
- A Swank-compatible MCP bridge can give the agent SLIME-like capabilities
  without reloading SBCL for every probe.

Limits:

- Full-suite runtime is dominated by test execution and allocation, not only
  startup, so a warm image does not materially replace CI-style validation.
- Live images can retain stale definitions. Final verification must still use
  `sbcl --script tests/run-tests.lisp` from a clean process.
- MCP eval tools are equivalent to local code execution. They should only bind
  to localhost and should not be enabled for untrusted workspaces.

Recommended next step: keep the CLI suite as the acceptance gate, and add an
optional MCP/Swank workflow for agent debugging. The smallest useful path is
`scripts/dev-image.lisp` plus `hanshuebner/lisp-mcp` pointed at
`ETHEREUM_LISP_SWANK_PORT=4005`. If we need richer introspection later, evaluate
`quasi/cl-mcp-server` behind the same localhost-only constraint.
