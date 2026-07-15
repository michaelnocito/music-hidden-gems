# Project Setup

How to rebuild this project's data environment from nothing. Every step offers two
ways: the point-and-click way, and the command-line way (kept in its own doc so the
steps here stay clean: [COMMAND_LINE.md](COMMAND_LINE.md)).

## Step 0a: Create the project folders

Target structure:

```
music-hidden-gems\
  data\        raw downloaded datasets (never edited by hand)
  queries\     the SQL walkthrough files
  docs\        this documentation
```

**Option A (no command line):** In File Explorer, go to `C:\Users\Mike\Projects`,
right-click > New > Folder, name it `music-hidden-gems`. Open it and create a
folder named `data` inside the same way.

**Option B (command line):** see [COMMAND_LINE.md, Step 0a](COMMAND_LINE.md#step-0a-create-the-project-folders).

## Step 0b: Download the Billboard Hot 100 history

The airplay half of the project: every Billboard Hot 100 chart week back to 1958
(~350,000 rows, ~19.5 MB), maintained by the University of Texas data-journalism
team in the [utdata/rwd-billboard-data](https://github.com/utdata/rwd-billboard-data) repo.

**Option A (no command line):** open this URL in a browser:
`https://raw.githubusercontent.com/utdata/rwd-billboard-data/main/data-out/hot-100-current.csv`
It renders as raw text. Press Ctrl+S and save it as `hot-100-current.csv` into the
`data` folder.

**Option B (command line):** see [COMMAND_LINE.md, Step 0b](COMMAND_LINE.md#step-0b-download-the-chart-data).

**Verify either way:** the file `data\hot-100-current.csv` exists and is roughly
19-20 MB. A file of only a few KB means the download grabbed an error page instead
of the data; delete it and retry.

## Step 1: Create the database

In DB Browser for SQLite: **New Database**, save as
`C:\Users\Mike\Projects\music-hidden-gems\data\music_gems.db`, and **Cancel** the
"Edit table definition" dialog that pops up (tables come from CSV imports, not
hand-building). All tables must live in this one .db file to be JOIN-able.

To reopen the project later: **Open Database** (not Import) and pick the .db file.

## Step 2: Import the chart CSV

**File > Import > Table from CSV file...** and pick `data\hot-100-current.csv`.
Set EVERY field in the dialog; DB Browser remembers the previous import's
settings, so never assume the defaults are right:

- **Table name:** `chart_entries` - and note the naming rule: underscores, never
  hyphens. DB Browser auto-fills the name from the filename (`hot-100-current`),
  which is legal but SQL reads hyphens as subtraction, forcing quotes around the
  name in every query forever.
- **Column names in first line:** CHECKED
- **Field separator:** `,` (comma)
- **Quote character:** `"` (double quote). With Quote = None, a title like
  `Let It Snow, Let It Snow, Let It Snow` splits at its internal commas, shifts
  the whole row rightward, and spawns phantom `field8`/`field9` columns. This
  happened on the first import attempt and was caught by eyeballing 20 rows.
- **Encoding:** UTF-8

Check the preview shows exactly 7 clean columns before clicking OK. Then **Write
Changes** (Ctrl+S) - the import is not saved to disk until you do.

Expected table: `chart_entries` with columns chart_week, current_week, title,
performer, last_week, peak_pos, wks_on_chart (~350k rows).

## Reading DB Browser's responses

- **"Execution finished without errors ... no rows returned" is NORMAL for any
  statement that builds or changes things** (CREATE TABLE, CREATE INDEX,
  CREATE VIEW). Those statements produce objects, not result grids; an empty
  result is success, not failure. Only SELECT statements return rows.
- Every CREATE is followed by a verification query in the walkthrough (count
  the new table, peek at its rows) because "it ran" and "it built what was
  intended" are two different facts.
- **Write Changes (Ctrl+S) after anything that builds or imports.** DB Browser
  holds changes in memory until you save; close without saving and the new
  table is gone.
