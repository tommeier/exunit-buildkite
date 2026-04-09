# ExUnitBuildkite

[![Hex.pm](https://img.shields.io/hexpm/v/exunit_buildkite.svg)](https://hex.pm/packages/exunit_buildkite)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/exunit_buildkite)
[![CI](https://github.com/tommeier/exunit-buildkite/actions/workflows/ci.yml/badge.svg)](https://github.com/tommeier/exunit-buildkite/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/exunit_buildkite.svg)](LICENSE)

Real-time Buildkite build annotations for ExUnit test failures. The Elixir
equivalent of [rspec-buildkite](https://github.com/buildkite/rspec-buildkite).

**Before:** Test failures are buried in log output. You find out what failed
after scrolling through hundreds of lines, or you add a separate `junit-annotate`
pipeline step that runs after all tests complete.

**After:** Each failure is annotated on the build the instant it happens — while
the rest of the suite is still running. No extra pipeline step, no JUnit XML, no
post-processing.

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔴 Test Failures                                   ── Build #42│
│                                                                 │
│ ▸ creates a customer with valid params                          │
│   — MyApp.CustomersTest (test/customers_test.exs:15)            │
│                                                                 │
│ ▸ rejects duplicate email addresses                             │
│   — MyApp.CustomersTest (test/customers_test.exs:42)            │
│                                                                 │
│   Click to expand each failure for the full assertion output.   │
└─────────────────────────────────────────────────────────────────┘
```

## Installation

Add `exunit_buildkite` to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exunit_buildkite, "~> 0.1", only: :test}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

## Quick Start

Add the formatter to `test/test_helper.exs` alongside the built-in CLI formatter:

```elixir
formatters =
  if System.get_env("CI") do
    [ExUnitBuildkite.Formatter, ExUnit.CLIFormatter]
  else
    [ExUnit.CLIFormatter]
  end

ExUnit.start(formatters: formatters)
```

That's it. Push to Buildkite and your next test failure will appear as a build
annotation in real-time.

> **Safe outside Buildkite** — if `buildkite-agent` isn't on `$PATH` (local dev,
> GitHub Actions, etc.), the formatter silently does nothing. No errors, no
> overhead.

## Configuration

Defaults work out of the box. Optionally configure via application env:

```elixir
# config/test.exs
config :exunit_buildkite,
  context: "exunit",
  style: "error"
```

| Option | Default | Description |
|--------|---------|-------------|
| `context` | `"exunit"` | Buildkite annotation context. Annotations with the same context are grouped together. Useful in monorepos to separate e.g. `"backend-tests"` from `"worker-tests"`. |
| `style` | `"error"` | Annotation style. One of `"error"`, `"warning"`, `"info"`, or `"success"`. Controls the color of the annotation banner in the Buildkite UI. |

Options can also be passed inline to the formatter — inline values take
precedence over application config:

```elixir
ExUnit.start(formatters: [
  {ExUnitBuildkite.Formatter, context: "backend-tests", style: "error"},
  ExUnit.CLIFormatter
])
```

### Monorepo Example

In a monorepo with multiple test suites, use `context` to keep annotations
separate:

```elixir
# apps/api/test/test_helper.exs
ExUnit.start(formatters: [
  {ExUnitBuildkite.Formatter, context: "api-tests"},
  ExUnit.CLIFormatter
])

# apps/worker/test/test_helper.exs
ExUnit.start(formatters: [
  {ExUnitBuildkite.Formatter, context: "worker-tests"},
  ExUnit.CLIFormatter
])
```

Each app's failures will appear in their own annotation block on the build page.

## How It Works

`ExUnitBuildkite.Formatter` is a `GenServer` that plugs into ExUnit's formatter
system. It receives the same events as the built-in `CLIFormatter`:

```
ExUnit runs tests
    │
    ├─ test passes → ignored
    │
    └─ test fails
         │
         ├─ Format failure with ExUnit.Formatter.format_test_failure/5
         │  (same output you see in the terminal)
         │
         ├─ Wrap in collapsible HTML <details> with test name + file:line
         │
         └─ Shell out to: buildkite-agent annotate --append --style error
            (appears on the build page immediately)
```

The formatter runs in its own process — it never blocks test execution. At the
end of the suite, ExUnit waits for all formatters to drain, so every failure is
guaranteed to be annotated before the step exits.

### Annotation Format

Each failure produces a collapsible `<details>` block:

```html
<details>
  <summary>
    <code>creates a customer with valid params</code>
    — MyApp.CustomersTest (<code>test/customers_test.exs:15</code>)
  </summary>
  <pre>
    1) creates a customer with valid params (MyApp.CustomersTest)
       test/customers_test.exs:15

       Assertion with == failed
       code:  assert customer.name == "Alice"
       left:  "Bob"
       right: "Alice"
  </pre>
</details>
```

## Migrating from junit-annotate

If you're using `junit_formatter` + the
[`junit-annotate`](https://github.com/buildkite-plugins/junit-annotate-buildkite-plugin)
Buildkite plugin, you can replace both with this single formatter.

### What to remove

**1. Remove `junit_formatter` from `mix.exs`:**

```diff
- {:junit_formatter, "~> 3.4", only: :test},
+ {:exunit_buildkite, "~> 0.1", only: :test},
```

**2. Remove `junit_formatter` config from `config/test.exs`:**

```diff
- config :junit_formatter,
-   report_dir: "tmp",
-   automatic_create_dir?: true,
-   print_report_file: true,
-   include_filename?: true
```

**3. Replace the formatter in `test/test_helper.exs`:**

```diff
  formatters =
    if System.get_env("CI") do
-     [JUnitFormatter, ExUnit.CLIFormatter]
+     [ExUnitBuildkite.Formatter, ExUnit.CLIFormatter]
    else
      [ExUnit.CLIFormatter]
    end
```

**4. Remove the JUnit XML upload from your test script:**

```diff
  mix test
-
- if [[ -f tmp/test-junit-report.xml ]]; then
-   buildkite-agent artifact upload tmp/test-junit-report.xml
- fi
```

**5. Remove the annotation pipeline step:**

If you have a separate `junit-annotate` step in your pipeline (YAML or DSL),
remove it entirely. Annotations now happen inline during the test step.

### What you gain

| | junit-annotate | exunit_buildkite |
|---|---|---|
| **Timing** | After all tests complete + separate step | Real-time, as each failure occurs |
| **Pipeline** | Extra step with `allow_dependency_failure` | No extra step |
| **Dependencies** | JUnit XML + Ruby-based plugin (Docker) | Zero — just `buildkite-agent` on PATH |
| **Artifacts** | Requires XML artifact upload | None |
| **Failure visibility** | Minutes after failure | Seconds after failure |

## Requirements

- **Elixir** `~> 1.17`
- **`buildkite-agent`** on `$PATH` in CI (standard on all Buildkite agents)

No other dependencies. The package depends only on ExUnit (part of Elixir) and
uses `buildkite-agent` via `System.cmd/3`.

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b my-feature`)
3. Make your changes
4. Run `mix test && mix format --check-formatted`
5. Open a pull request

### Releasing

Maintainers: use `bin/release <major|minor|patch>` to bump, tag, and publish.
Requires `HEX_API_KEY` env var for Hex publishing.

## License

MIT — see [LICENSE](LICENSE).
