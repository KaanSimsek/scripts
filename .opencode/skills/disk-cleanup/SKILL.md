---
name: disk-cleanup
description: Use when the user wants to free up disk space on their Mac or asks to find/remove caches, logs, Xcode build data, npm caches, Trash contents, or files larger than 1 GB. This skill runs the repository's cleanup.sh safely: list first, then delete only the exact items the user approved.
---

# Disk Cleanup

This skill uses `cleanup.sh` at the repository root. The script scans first and
deletes only items the user explicitly approves. The default behavior is to
delete nothing.

## Core rule

Never delete anything until the user approves specific IDs. "Free up space" or
"clean up" is not permission to delete; show the findings and ask what should be
removed. If you are unsure, ask again.

## Workflow

1. Locate the repo root and confirm the script exists:

   ```bash
   git rev-parse --show-toplevel
   ./cleanup.sh --help
   ```

   If the script is missing, tell the user; do not invent delete commands.

2. Get the machine-readable report (it may be slow because it scans for files
   over 1 GB):

   ```bash
   ./cleanup.sh --json
   ```

   Validate it with `jq .` if available, otherwise `python3 -m json.tool`. JSON
   fields: `disk`, `total_reclaimable_kb`, `items[]` (`id`, `kind`, `name`,
   `path`, `size_kb`, `entries`). `kind` is `category` (known cache/log) or
   `file` (a single file over 1 GB).

3. Show the findings as a short table: disk usage percentage, total reclaimable
   space, and the largest few items (ID, size, path). Summarize instead of
   dumping the full list; show everything only if the user asks.

4. Ask the user two questions together:
   - Which IDs should be removed? (e.g. `2,7,12`)
   - Should they be moved to Trash (recoverable) or permanently deleted?

   Recommend Trash by default. Use permanent deletion only when the user
   explicitly says "delete permanently". If the user says "delete everything"
   without giving IDs, list exactly what would be included and ask again.

5. Run the approved operation:

   ```bash
   ./cleanup.sh --trash 2,7,12
   # or only with explicit approval:
   ./cleanup.sh --delete 2,7,12 --yes
   ```

6. Report the result: space cleaned and space remaining. If items were moved to
   Trash, remind the user that the Trash must be emptied for the space to be
   reclaimed. If the user wants to empty the Trash, `--trash 1` can be used;
   tell them it is irreversible.

## Command summary

| Command | Effect |
| --- | --- |
| `./cleanup.sh --list` | Human-readable report, deletes nothing |
| `./cleanup.sh --json` | Machine-readable report, deletes nothing |
| `./cleanup.sh --trash <ids>` | Moves selected items to Trash |
| `./cleanup.sh --delete <ids> --yes` | Permanently deletes selected items |
| `./cleanup.sh` | Interactive mode (real terminal only) |

IDs are reassigned on every run. Do not reuse an ID from one report in a later
run; get a fresh report right before deleting, or use the IDs from the same run.

## Safety boundaries

- Do not use `sudo`. The script only cleans the user's home directory.
- Do not run `--delete` without the user's approval; do not add `--yes` on the
  user's behalf.
- Do not delete `~/Library/CloudStorage`, system directories, or paths outside
  the home directory. The large-file scan already skips CloudStorage.
- Do not modify the script's confirmation checks, safety checks, or the `--yes`
  requirement.
- If the user says "everything", explain that this covers all categories but not
  files over 1 GB.
- When a path may contain user data (Xcode Archives, application support, large
  media), show its size and path and leave the decision to the user.

## Tips

- Change the threshold: `LARGE_FILE_GB=5 ./cleanup.sh --json`
- Change how many large files are listed: `MAX_LARGE_FILES=50 ./cleanup.sh --json`
- The script's output and prompts are in Turkish; answer the user in the
  language they use.
- Piping the output (`| head`) can cause `SIGPIPE`; redirect the report to a file
  (`> /tmp/cleanup.json`) and read it afterward.
