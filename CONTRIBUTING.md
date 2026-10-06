# Contributing to Runika

Use Bend 2.0.35 for the current baseline. Read `bend guide` before editing Bend
and keep project text in English. Library implementation belongs in Bend; the
official runtime and operating system remain external dependencies.

Clone [Splina](https://github.com/amage-si/splina) next to Runika (as `Splina`),
and install Liberation Sans 2.1.5 at
`/usr/share/fonts/liberation/LiberationSans-Regular.ttf` (see the README).

## Validation

From the repository root:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
bend examples/outline.bend -o build/outline
./build/outline --threads 2 --gpu off
```

When parsing changes, also run the independent comparison with fontTools
(a test oracle only; nothing in the library uses it):

```sh
bend tools/reference_dump.bend -o build/reference-dump
./build/reference-dump --threads 2 --gpu off > build/bend-reference.jsonl
python3 -m venv build/venv
build/venv/bin/pip install fonttools==4.66.1
build/venv/bin/python tools/fonttools_reference.py build/bend-reference.jsonl
```

Syllo and Dithra build on Runika. If you change a public type or function,
build their test suites with Runika in place before proposing the change.

Build one target at a time. The native Bend runtime reserves substantial virtual
address space; a virtual-memory limit is not a resident-memory limit. Preserve
crash evidence and investigate before repeating a failed compiler invocation.

## Changes

Keep the API small and errors explicit. Add a focused regression check when
behavior changes, including a malformed-input case for each new table or field,
update affected contracts, and report what was actually validated.

Use English commit messages that explain the result. Do not commit `build/`,
generated C, logs, crash dumps, font files, credentials, or machine-specific
paths. Do not publish BendHub packages or create releases as a side effect of
validation.
