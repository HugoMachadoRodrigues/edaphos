# Check whether a local Ollama server is reachable

Issues a short GET request to the Ollama `/api/tags` endpoint and
reports whether the server responds. Used by
[`llm_kg_pipeline_run()`](https://hugomachadorodrigues.github.io/edaphos/reference/llm_kg_pipeline_run.md)
as a pre-flight gate.

## Usage

``` r
llm_kg_ollama_check(
  host = "http://localhost:11434",
  model = NULL,
  timeout_sec = 1
)
```

## Arguments

- host:

  Character; the base URL of the Ollama server. Default
  `"http://localhost:11434"`.

- model:

  Optional character; if supplied, additionally verifies that the named
  model is present on the server.

- timeout_sec:

  Numeric; HTTP timeout. Default `1`.

## Value

A named list. `reachable` (logical) is always present. `model_present`
(logical) and `models_available` (character) are added only when `model`
is non-NULL *and* the server is reachable – on an unreachable server
they are absent, not `FALSE`.

## Examples

``` r
# The gate is deliberately cheap and never throws: a refused
# connection comes back as a plain FALSE, so a batch script can
# branch on it.  Port 1 is always closed.
llm_kg_ollama_check(host = "http://127.0.0.1:1", timeout_sec = 0.5)
#> $reachable
#> [1] FALSE
#> 

# `reachable` is not "the port is open".  httr2 raises on 4xx/5xx,
# so the `status < 400` test in the body is never reached and a
# host that answers 404 on /api/tags is indistinguishable from a
# refused connection.  In the other direction, anything that
# answers 200 counts as reachable -- which is why the model check
# below, not `reachable`, is what tells you it is really Ollama.

# Read `model_present` next to `reachable`, never on its own: when
# the server is down the element is ABSENT, not FALSE.
chk <- llm_kg_ollama_check(host = "http://127.0.0.1:1",
                           model = "gemma4:latest", timeout_sec = 0.5)
names(chk)                              # "reachable" alone
#> [1] "reachable"
try(if (!chk$model_present) "missing")  # error: invalid argument type
#> Error in !chk$model_present : invalid argument type
isFALSE(chk$model_present)              # FALSE -- the safe idiom,
#> [1] FALSE
                                        # and the one the pipeline uses
if (FALSE) { # \dontrun{
# Against a live `ollama serve` the result gains the two extra
# elements; `models_available` is what you print when the model
# check fails, so the user knows what was actually pulled.
chk <- llm_kg_ollama_check(model = "gemma4:latest")
chk$model_present
chk$models_available
} # }
```
