# Data Quality: What Was Wrong, What Clued Us In, How It Was Validated

A running record of every data-quality issue found in this project: the clue that
something was off, the check that confirmed it, and the professional concept each
one teaches. Updated as the walkthrough progresses.

## Issue 1: The import silently split rows apart

**The clue.** The imported table showed 9 columns, but the CSV's header names
only 7. DB Browser had invented `field8` and `field9` for data that had no
header name. Extra unnamed columns are never free bonus data; they mean rows
are wider than the header, which means something is splitting rows wrong.

**The validation.** `SELECT * ... LIMIT 20` on the raw table. Row 12 showed the
title "Let It Snow, Let It Snow, Let It Snow" chopped into three columns, with
the artist (Dean Martin) shoved into the peak-position column. Cause: the import
dialog's Quote character was set to None (DB Browser silently remembers whatever
the previous import used), so commas INSIDE quoted titles were treated as column
breaks. Fix: delete the table, re-import with Quote = `"`, re-peek, confirm the
title intact and exactly 7 columns.

**Professional concepts.**
- **Never analyze a table you haven't looked at.** Eyeballing 20 real rows costs
  seconds and catches whole classes of import damage.
- **Column count is a contract.** Data columns must equal header columns; any
  mismatch is a structural defect to explain before any query runs.
- **Never assume dialog defaults.** Import tools remember previous settings.
  Spell out every field (separator, quote, encoding, header) every time.
- **Raw files are read-only.** The fix re-imported from the untouched CSV; the
  broken table was deleted, the source file never edited.

## Issue 2: Row count vs expectation

**The clue.** None; this is a check you run BEFORE anything looks wrong,
because import tools can drop thousands of rows without an error message.

**The validation.** Build the expectation first, from knowledge of the data:
the Hot 100 lists 100 songs per week, 1958 to present, so roughly 68 years x 52
weeks x 100 = ~350,000 rows. `COUNT(*)` returned 354,500 - in range, and exactly
divisible by 100. Then verify the hint instead of trusting it:
`COUNT(DISTINCT chart_week)` returned 3,545 weeks, and 3,545 x 100 = 354,500
exactly. Every chart week is complete, coverage 1958-08-04 to 2026-07-11.

**Professional concepts.**
- **Expected vs actual row count** is the cheapest data-integrity test there is.
  Compute what the number SHOULD be from first principles, then compare.
- **Arithmetic cross-checks.** Two independent queries (total rows, distinct
  weeks) must agree with each other. Agreement from different angles is far
  stronger evidence than either number alone.

## Issue 3: Number columns that imported as TEXT

**The clue.** `last_week` and `peak_pos` are chart positions - numbers - yet
the import typed them TEXT. An importer only falls back to TEXT when at least
one value in the column isn't numeric. That is a fact about the data, and it
has to be found, because text math fails SILENTLY: as text, '9' sorts after
'100', and comparisons quietly give wrong answers instead of errors.

**The validation, in stages (each stage narrows the hunt):**
1. Hypothesis 1: blank cells. `WHERE last_week = '' OR peak_pos = ''` counted 0.
   Hypothesis rejected; blanks are not the cause.
2. Hypothesis 2: any non-digit value. `WHERE last_week GLOB '*[^0-9]*'` (flag
   any value containing a character that is not 0-9) found the answer:
   `last_week` holds the text **'NA'**, the R language's "not available" marker
   (the source repo's data pipeline runs in R).
3. A contradiction surfaced along the way: the Step 3 peek had shown a debut
   song with `last_week = 0`, so the file may mark "no previous week" TWO
   different ways (0 and 'NA') - a hint the archive was stitched together from
   different sources or eras. And no non-numeric `peak_pos` value appeared,
   leaving its TEXT type unexplained. Both go to a counting query
   (`SUM(test)` per oddity) before any conclusion is drawn.

**Professional concepts.**
- **Column types are evidence.** A numeric column arriving as TEXT is the
  import tool telling you it saw something non-numeric. Chase it down.
- **Missing-value markers vary by tool.** R writes 'NA', other tools write
  NULL, '', 'N/A', 0, or -1. Multiple markers in one column usually means
  multiple upstream sources.
- **Hypothesis-driven debugging.** Guess, test, reject, narrow: blanks first
  (cheapest test), then a pattern hunt (GLOB), then counts. Each query is a
  question with a yes/no answer, not a fishing trip.
- **Quantify before deciding.** Finding an oddity is not enough; its COUNT
  decides the handling. A handful of rows gets documented and stepped around;
  hundreds of thousands mean the oddity is part of the data's language.
- **CAST before math.** Any numeric comparison or sort on these TEXT columns
  must convert explicitly (`CAST(peak_pos AS INTEGER)`), and only after the
  non-numeric values are known and handled.

## Issue 4: One artist, seven names (entity resolution)

**The clue.** The top-25 most-charted-artists list showed "Elvis Presley With
The Jordanaires" as its own artist with 53 songs. A backing band in the credit
string means the same real-world artist almost certainly appears under other
credit strings too, splitting his catalog across rows.

**The validation.** `WHERE performer LIKE '%Elvis Presley%'` grouped by exact
credit. Seven distinct credit strings came back:

| Credit string | Songs |
|---|---|
| Elvis Presley With The Jordanaires | 53 |
| Elvis Presley | 50 |
| Elvis Presley With The Mello Men | 2 |
| Elvis Presley vs JXL | 1 |
| Elvis Presley With The Jubilee Four And Carole Lombard Quartet | 1 |
| Elvis Presley With The Jordanaires, Jubilee Four & Carol Lombard Trio | 1 |
| Elvis Presley With The Jordanaires and The Imperials Quartet | 1 |

One artist, seven representations, catalog split nearly in half between the top
two. Note the fragments have their own inconsistencies ("Carole Lombard
Quartet" vs "Carol Lombard Trio") - messy data is messy all the way down.

**Professional concepts.**
- **Entity resolution** (also record linkage, deduplication): recognizing that
  multiple data representations refer to one real-world entity. One of the
  most common problems in professional data work (customer names, vendor
  lists, addresses), and it is exactly why "count by exact string" understates
  every artist with credit variants.
- **Measure before designing.** The severity of fragmentation, not an
  assumption about it, decides whether exact strings are usable or
  normalization rules are required. Here, exact strings would undercount the
  biggest legacy artists by roughly half, so normalization is mandatory.
- **GROUP BY exact value is the measuring tool.** The same query shape that
  produced the wrong-looking leaderboard is the one that diagnoses why it is
  wrong, just pointed at one entity with LIKE.

### Sizing the problem: why "Featuring", "With", and "&"

The three patterns tested were not guessed; they were the joiner words
observed in the actual query outputs (the top-25 leaderboard and the Elvis
variants both showed credits built with "Featuring", "With", and "&"). Counts
across 11,275 distinct credit strings: "Featuring" 2,662, "With" 244, "&"
1,994 - up to ~43% of all credits carry a joiner, making joiner-handling a
core design requirement for the artists table.

**Best practices this illustrates:**
- **Derive patterns from the data, not from imagination.** Candidate joiners
  come from reading real rows (profiling output), then each candidate is
  counted before it earns a place in any cleaning rule. A pattern that
  matches almost nothing is noise; one that matches thousands shapes the
  design.
- **Patterns are a starting list, not a finished one.** Other joiners ("X",
  "vs", "Duet With", "And") may exist; the list grows by iterating: apply
  the known patterns, eyeball what still looks combined, add and re-count.
  This is genuinely how normalization rules get built in practice: iterate
  until the exceptions stop appearing. In this project the ladder grew one
  rung at a time, each caught by previewing real rows: ' With ' mangled
  "2Pac Duet With Mopreme" (add ' Duet With ' above it), then ' Duet With '
  mangled "Patti Austin A Duet With James Ingram" (add ' A Duet With ' above
  that). Rule order matters: each more specific pattern sits above the
  general pattern it contains, because the first match wins.
- **Count the false positives before splitting.** "&" is dangerous: it joins
  collaborators ("Drake & Future") but it also lives INSIDE permanent band
  names ("Hall & Oates", "Earth, Wind & Fire"). A blind split-on-& would
  shred real band names into fake artists. Any splitting rule must first be
  tested against the credits it would change, and the exceptions counted.
- **Whitespace matters in pattern tests.** The tests use ' Featuring ' with
  surrounding spaces so words like "Withers" or a band named "Withrow" don't
  false-match. Pattern precision is cheap insurance.

## Issue 5: A table that existed in one program and not the other

**The clue.** The Python fetch script crashed with `no such table:
known_artists` -- while DB Browser, open at the same time, showed the table
plainly in its Database Structure tab.

**The validation.** Listing the tables actually inside the `.db` FILE (from
outside DB Browser) showed only `chart_entries` and `artist_songs`, plus a
`music_gems.db-journal` file sitting next to the database. That journal is DB
Browser's holding area for uncommitted changes: the CREATE TABLE had run in
the app but was never written to the file. One click of **Write Changes** in
DB Browser, and re-listing the file showed all three tables; the script then
found its roster (1,570 rows, matching the count measured before the build).

**Professional concepts.**
- **A database change isn't real until it's committed.** DB Browser batches
  changes and only writes them to the file on Write Changes. Every tool with
  a "pending changes" model (databases, git, many editors) has this trap.
- **Two programs share a file, not a session.** Anything outside DB Browser
  (a script, another app, a backup) sees only what has been committed.
- **The error message names the missing thing, not the cause.** "No such
  table" sounded like the table was never built; the real cause was one
  unclicked button. Verify state from a second vantage point before
  re-doing work.

## Issue 6: One song, several track names (entity resolution, track edition)

**The clue.** The first 20 rows of the imported `lastfm_tracks` table showed
"Amish Paradise (Parody of ""Gangsta''s Paradise"" by Coolio)" AND a plain
"Amish Paradise" as two separate tracks with separate playcounts -- and
"White & Nerdy" duplicated the same way.

**The validation.** Eyeballing the import peek (SELECT * ... LIMIT 20). No
query needed yet; the duplication is visible on sight. The scale of it gets
measured before the join step, because joining chart titles to Last.fm titles
by text means every name variant is a potential missed match.

**Professional concepts.**
- **Entity resolution appears on every axis of a dataset.** The chart data
  fragmented ARTISTS across credit strings; the Last.fm data fragments
  SONGS across name variants. Same problem, new column. Expect it anywhere
  humans (or their music players) type names.
- **Crowd-sourced data mirrors the crowd.** Last.fm records whatever track
  title users'' players report, so popular songs accumulate variant
  spellings. High-traffic entities fragment MORE, not less.
- **Log now, handle at the join.** The issue is recorded when first seen,
  and dealt with where it actually bites (the title-matching step), with a
  match-rate check to measure how much it cost.

## A note on the clean import (what NOT finding problems looks like)

The `lastfm_tracks` import is also worth a record precisely because its
number columns (`playcount`, `listeners`) arrived as INTEGER, unlike the
chart side''s `peak_pos`, which imported as TEXT and triggered a whole
investigation (Issue 3). The difference is the source: API data is generated
by a program from a database, so its fields are uniform; the chart archive
was stitched from decades of differently-marked eras. Fresh machine-made
data tends to be typed cleanly; long-lived human-curated archives tend not
to be. Checking types after EVERY import is how you find out which kind you
are holding.

## Issue 7: Case-twin artists (Tyler, The Creator vs Tyler, the Creator)

**The clue.** The parenthetical-title peek (Step 19b) showed the same track
twice with identical playcounts, under "Tyler, The Creator" and "Tyler, the
Creator" -- one artist, two capitalizations.

**The validation.** Grouping the roster by LOWER(primary_artist) and keeping
groups with more than one row (Step 20). Exactly three real artists are
split by capitalization alone: Tyler, the Creator; JAY-Z; Charli XCX --
6 roster rows for 3 people, 0.2% of the 1,570-artist roster. Because the
roster drove the API pull, each twin''s tracks were fetched twice.

**The decision.** No rebuild. Every text join in the gem query uses LOWER()
on both sides, which merges the case twins and collapses their duplicated
tracks in the same move. Cost: none measurable at this scale; the twins are
listed here so the number is on record.

**Professional concepts.**
- **Capitalization is an entity-resolution axis too.** After joiner words
  (artists) and name variants (tracks), letter case is the third way one
  real-world thing became several strings in this project alone.
- **Quantify before choosing the fix.** 0.2% justified a query-time
  LOWER(); 20% would have justified rebuilding the roster. The measurement
  chose the remedy.
- **Case-insensitive keys are the default for human-typed text.** Joining
  names without LOWER() (or the equivalent) is betting that every source
  capitalized identically. Real sources never do.
