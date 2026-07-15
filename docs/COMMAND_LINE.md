# Command-Line Companion (PowerShell)

The command-line versions of the setup steps in [SETUP.md](SETUP.md), with each
command explained. The command line is the industry-standard way to scaffold a
data project: faster than clicking, repeatable, and the exact commands can be
pasted into documentation so anyone can rebuild the setup.

To open PowerShell: press the Windows key, type `powershell`, press Enter.

## Step 0a: Create the project folders

Read out loud, one line per command:

```
--mkdir   "make directory": create a folder at the given path. PowerShell
          creates every missing level of the path at once, so one command
          makes Projects\music-hidden-gems AND data inside it in one move.
--cd      "change directory": move the terminal INTO a folder, so later
          commands run from there and can use short relative paths.
--ls      "list": show what is inside the current folder; the terminal
          version of looking at the folder window.
```

The commands:

```powershell
mkdir C:\Users\Mike\Projects\music-hidden-gems\data
cd C:\Users\Mike\Projects\music-hidden-gems
ls
```

Expected result: `ls` prints a table with one entry, `data`, showing `d-----` at
the left of its row (`d` = directory, meaning folder).

## Step 0b: Download the chart data

Read out loud:

```
--curl     fetch a file from the internet
---o       "output": save the fetched file under the path that follows
           (data\hot-100-current.csv is a RELATIVE path: it works because
           Step 0a ended with the terminal sitting inside music-hidden-gems)
--the URL  the raw CSV straight from the source GitHub repo
```

The command (one line):

```powershell
curl -o data\hot-100-current.csv https://raw.githubusercontent.com/utdata/rwd-billboard-data/main/data-out/hot-100-current.csv
```

Verify:

```powershell
ls data
```

Expected result: one file, `hot-100-current.csv`, with a `Length` (bytes) around
19-20 million. A Length of only a few thousand means an error page was downloaded
instead of the data; delete the file and retry.
