# fetch-metadata

This project provides a command-line tool to fetch book metadata using an ISBN.

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
    cd /home/jan/own/fmd.nvim/fetchfunctions/fetch-metadata
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
