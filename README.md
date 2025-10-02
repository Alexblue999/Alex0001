# Alex0001

This repository now includes a helper script for bootstrapping dependencies across
multiple ecosystems.

## Initialize all libraries

Run the following command from the project root to automatically detect common
manifest files (such as `package.json`, `requirements.txt`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, and more) and install their dependencies with the
appropriate package manager when available:

```bash
scripts/init_all_libs.sh
```

Use the `--dry-run` flag to preview what would be executed without running any
commands:

```bash
scripts/init_all_libs.sh --dry-run
```

The script will create isolated Python virtual environments inside each project
directory when necessary (`.venv/`) and gracefully skip package managers that
are not installed on your system.
