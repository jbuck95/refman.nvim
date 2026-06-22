# fetch-metadata

**DEMO**

![Demo](<insert-video-link>)

## Description

Command-line tool to fetch book metadata using an ISBN, used by the refman.nvim plugin.

## Disclaimer

These functions are from Kovid Goyal's Calibre:
> https://github.com/kovidgoyal/calibre

## Global Installation

To install `fetch-metadata` globally on your system, it is recommended to use `pipx`.
`pipx` installs Python applications into isolated environments to prevent dependency
conflicts, while still making them available directly from your command line.

### Prerequisites

Make sure you have `pipx` installed. If not, you can install it using `pip`:

```bash
python3 -m pip install --user pipx
python3 -m pipx ensurepath
```

You might need to restart your terminal or source your shell configuration file
(e.g., `~/.bashrc`, `~/.zshrc`) after running `pipx ensurepath` for the changes to
take effect.

### Installation Steps

1.  Navigate to the project's root directory:
    ```bash
    cd <plugin-dir>/scripts/fetch-metadata
    ```

2.  Install the `fetch-metadata` tool using `pipx`:
    ```bash
    pipx install .
    ```

### Usage

After installation, you can use the `fetch-metadata` command from any directory:

```bash
fetch-metadata --isbn 978-0345391803
```

This will fetch and display metadata for the specified ISBN.
