# File Monitor for Bash

Monitors files for changes via inotifywait and executes a command when a change is detected.

## Usage

```bash
# Run in interactive mode
./monitor.sh
```

```
Usage:
  ./monitor.sh [OPTION]

Options:
  -l, --list		list active monitors
  -r, --reload		reload all monitors
  -k, --kill		kill and delete all monitors
  -h, --help		display this help and exit
```

