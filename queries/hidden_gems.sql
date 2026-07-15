-- ############################################################
-- #  MUSIC HIDDEN GEMS                                        #
-- #  "Which songs by known artists did radio bury?"           #
-- #  Data 1: Billboard Hot 100 weekly history, 1958-present   #
-- #          (utdata/rwd-billboard-data, UT-Austin journalism)#
-- #  Data 2: Last.fm API track stats (playcount + listeners)  #
-- #          -- fetched by scripts/fetch_lastfm.py            #
-- #  Tools: SQLite + DB Browser for SQLite; two Python        #
-- #         data-collection scripts                           #
-- ############################################################

-- ============================================================
-- ABOUT THIS FILE
-- The question: which songs by KNOWN artists did radio bury?
--   "Known artist" = an artist the Hot 100 has charted multiple
--     times (radio demonstrably knows who they are).
--   "Buried song"  = a track by that artist that the listeners
--     who found it replay heavily (high plays-per-listener on
--     Last.fm) but that never charted.
--   "Hidden"       = found by a modest audience (a fame ceiling
--     added in Step 31 after reading real results -- famous
--     never-charted songs became their own "buried anthem" tier).
-- The chart table knows what radio pushed; the Last.fm table
-- knows what listeners love. Only a JOIN can hold both facts
-- about one song at once.
--
-- THIS FILE IS SQL ONLY. The project has exactly two non-SQL
-- steps: SQL cannot call the internet, so Last.fm data is
-- collected by small Python scripts (scripts/fetch_lastfm.py
-- and scripts/fetch_lastfm_details.py, taught the same way:
-- boxed WHY + read-out-loud comments, which in Python start
-- with # instead of --). Their output CSVs come back into this
-- database, and everything else is SQL.
--
-- Companion docs (in docs/):
--   SETUP.md            rebuild the folders, downloads, database
--   COMMAND_LINE.md     the terminal versions of setup, explained
--   JOINS_GUIDE.md      joins from zero: keys, join types, ON vs
--                       WHERE, compound keys, anti-joins
--   HOW_TO_STUDY.md     how to learn from this file (rehearse method)
--   CASE_GUIDE.md       CASE expressions from zero
--   DATA_QUALITY.md     every issue found: clue, validation, concept
--   WHY_WE_CHECK_DATA.md  the discipline behind the checks
--   GET_AN_API_KEY.md   what APIs and API keys are, getting the
--                       free Last.fm key, storing it safely,
--                       running the fetch scripts
--   DATA_DRIVEN_THRESHOLDS.md  how every cutoff in this file was
--                       chosen from measured distributions
--   EXTEND_THIS_PROJECT.md  ways to push the analysis further
--                       with the skills this file teaches
-- ============================================================

-- ============================================================
-- SQL FUNCTIONS & KEYWORDS USED (quick reference)
-- SELECT        which columns to display
-- FROM          which table to pull from
-- WHERE         keep only rows passing a test
-- GROUP BY      collapse rows into one row per group
-- HAVING        like WHERE, but tests the GROUPS after collapsing
-- ORDER BY      sort the results (DESC = biggest first)
-- LIMIT         only show the first N rows
-- COUNT(*)      how many rows
-- COUNT(DISTINCT x)  how many different values of x
-- MIN(x)/MAX(x) smallest / largest value in the group; on TEXT,
--               alphabetically first / last
-- ROUND(x, 2)   trim a decimal to 2 places
-- CAST(x AS REAL)    treat text/integer as a decimal number
-- AS            give a column or table a nickname (alias)
-- LOWER(x)      lowercase text (for matching messy text keys)
-- TRIM(x)       strip stray spaces off both ends
-- LIKE          fuzzy text test ('%live%' = contains "live")
-- OR            combine two WHERE tests; a row passes if EITHER is true
-- GLOB          pattern test; [^0-9] inside it = "a non-digit character"
-- SUM(test)     a comparison returns 1/0, so SUM of it counts passing rows
-- (subquery)    a query in parentheses used as a table by an outer query
-- INSTR(x, y)   position where text y first appears inside x (0 if
--               absent); positions count from 1
-- SUBSTR(x, a, b)  cut a piece of text x starting at position a,
--               b characters long
-- CASE WHEN ... THEN ... ELSE ... END   if/else for a value; the
--               first matching WHEN wins, ELSE is the fallback
-- INNER JOIN ... ON  combine two tables where the keys match
-- LEFT JOIN ... ON   same, but keep left rows even with no match
-- IS NULL       test for "no value here" (powers the anti-join)
-- CREATE TABLE ... AS   save a query's result as a new table
-- DROP TABLE IF EXISTS  delete a table if present, so a build
--               step can be re-run safely from the top
-- DELETE FROM ... WHERE  remove rows matching a test (only ever
--               used on DERIVED tables here -- raw data is
--               read-only and derived tables rebuild)
-- CREATE INDEX  build a sorted lookup on the columns a join
--               searches by, so the join runs in seconds
-- PERCENT_RANK() OVER (ORDER BY x)  a WINDOW FUNCTION: gives each
--               row the fraction of rows ranked below it on x
--               (0 = lowest, 1 = highest) WITHOUT collapsing rows
--               the way GROUP BY does
-- printf('%02d', n)  format a number as text, zero-padded to 2
--               digits (7 -> '07') -- used to build m:ss durations
-- ============================================================

-- ============================================================
-- LOVE-PER-LISTENER (the gem signal)
-- Last.fm reports, per track:
--   listeners  = how many distinct people ever played it
--   playcount  = total plays across all of them
-- playcount / listeners = average plays PER PERSON who found the
-- song. Raw playcount just measures fame. Plays-per-person
-- measures devotion: a song only 50,000 people found, but each
-- played 40 times, is loved harder than a radio staple everyone
-- heard twice. High devotion + absent from the chart = buried.
-- Every threshold here (how many listeners is "enough"? what
-- counts as "high" devotion? how famous is too famous to be
-- "hidden"?) is set FROM the data -- see the distribution steps
-- and docs/DATA_DRIVEN_THRESHOLDS.md.
-- ============================================================

-- ============================================================
-- SHRINK LEDGER (running row counts as steps confirm)
--   chart_entries imported ............ 354,500
--   distinct chart weeks .............. 3,545 (x 100 = 354,500)
--   distinct performer credits ........ 11,275
--   artist_songs (one row per song) ... 32,631
--   distinct primary artists .......... 8,896 (from 11,275 credits)
--   known_artists (5+ songs) .......... 1,570
--   lastfm_tracks imported ............ 78,335 (from 1,570 artists)
--   devoted_tracks (1k+ / 6+ ratio) ... 13,090
--   matched to a chart song ........... 5,059 (38.6%)
--   gems (never charted, deduped) ..... 7,828
--   version variants removed .......... 136  ->  7,692 gems
--     hidden gem (< 200k listeners) ... 4,657 before cleanup
--     middle band (200k - 1M) ......... 2,862 before cleanup
--     buried anthem (1M+) ............. 309 before cleanup
--   top_gems (enrichment roster) ...... 500 (Step 39 rebuild:
--     500 DISTINCT top-40 artists, one gem each)
--   gem_details (album/tags/duration) . 500 (from API)
--   gem_page (final web dataset) ...... 500
-- ============================================================

-- ============================================================
-- DATA NOTES (facts verified at import; setup itself is in
-- docs/SETUP.md)
-- Import settings are spelled out in docs/SETUP.md and set
-- explicitly EVERY time, because DB Browser silently remembers
-- whatever the previous import used. The settings that matter:
-- separator = comma, quote = " (a title like "Let It Snow, Let
-- It Snow, Let It Snow" has commas inside that only the quote
-- character protects), encoding = UTF-8, column names in first
-- line = CHECKED.
-- chart_entries columns:
--   chart_week TEXT, current_week INTEGER, title TEXT,
--   performer TEXT, last_week TEXT, peak_pos TEXT,
--   wks_on_chart INTEGER
-- last_week and peak_pos imported as TEXT not INTEGER; the
-- investigation in Steps 6-6d found why and what to do about it.
-- Debut songs carry last_week = 'NA' or '0' (both).
-- lastfm_tracks columns: artist TEXT, track TEXT,
--   playcount INTEGER, listeners INTEGER -- both numbers typed
--   INTEGER because API data is machine-generated and uniform;
--   the decades-stitched chart archive was not. Check types
--   after EVERY import to learn which kind you are holding.
-- DB Browser holds changes in a journal until Write Changes
-- (Ctrl+S). Tables you can see in DB Browser are INVISIBLE to
-- scripts and other programs until written -- docs/
-- DATA_QUALITY.md Issue 5 records the hour this cost.
-- ============================================================

-- ============================================================
-- STEP 3: PEEK AT THE RAW TABLE
-- WHY: never analyze a table you haven't looked at. The first
-- import attempt here proved the point: it ran with Quote =
-- None, which split comma-containing titles across columns and
-- spawned two phantom columns (field8/field9) -- caught only by
-- eyeballing real rows before trusting anything. This peek
-- checks that titles hold titles, performers hold artists, and
-- every column landed where the header says it should.
-- RESULT: 20 rows, 7 clean columns after re-import. "Let It
-- Snow, Let It Snow, Let It Snow" / Dean Martin intact on one
-- row. Debut songs show last_week = 0 (Broadway Girls, week 1).
-- ============================================================

--SELECT every column (* = all of them)
--FROM the chart_entries table (pull from)
--LIMIT only show the first 20 rows
SELECT *
FROM chart_entries
LIMIT 20;

-- ============================================================
-- STEP 4: HOW BIG IS THE TABLE?
-- WHY: every analysis needs its starting row count on record --
-- it is the top line of the shrink ledger, and it verifies the
-- import didn't silently drop rows. A wrong quote or separator
-- setting can swallow thousands of rows without any error
-- message, and a row count against expectations is the cheapest
-- way to catch it. Expectation here: the Hot 100 lists 100 songs
-- a week and the file spans 1958 to the present, roughly 68
-- years x 52 weeks x 100 = ~350,000 rows.
-- RESULT: 354,500 rows -- in range, and exactly divisible by
-- 100, hinting at 3,545 complete 100-song charts. Step 5 checks
-- that hint instead of trusting it.
-- ============================================================

--SELECT the count of all rows (display)
--FROM the chart_entries table (pull from)
SELECT COUNT(*)
FROM chart_entries;

-- ============================================================
-- STEP 5: HOW MANY WEEKS, AND WHAT DATE RANGE?
-- WHY: 354,500 rows / 100 = 3,545 -- but that math only proves
-- divisibility, not that every chart week really has 100 songs.
-- This query counts the DISTINCT chart weeks and finds the first
-- and last chart date, establishing the table's true coverage.
-- If distinct weeks x 100 = total rows, every week is complete.
-- The date range also matters later: any song released after the
-- last chart_week can't be judged "never charted" fairly.
-- RESULT: 3,545 weeks x 100 = 354,500 -- every week complete.
-- Coverage 1958-08-04 (the first Hot 100 ever published) through
-- 2026-07-11. Full chart history, no partial weeks.
-- ============================================================

--SELECT the number of different chart weeks (display)
--  * COUNT(DISTINCT chart_week)  counts each week once, no matter
--    how many songs it lists
--  * MIN(chart_week)  the earliest chart date in the table
--  * MAX(chart_week)  the latest chart date in the table
--FROM the chart_entries table (pull from)
SELECT COUNT(DISTINCT chart_week) AS weeks,
       MIN(chart_week) AS first_week,
       MAX(chart_week) AS last_week
FROM chart_entries;

-- ============================================================
-- STEP 6: WHY ARE last_week AND peak_pos TEXT?
-- WHY: chart positions are numbers, yet the import typed
-- last_week and peak_pos as TEXT. An importer only does that
-- when at least one row holds something that isn't a number --
-- and whatever that something is must be found BEFORE any math
-- (comparisons, MIN, sorting) touches these columns, because
-- text math fails silently: '9' sorts AFTER '100' as text.
-- This query counts rows where either column is empty text.
-- RESULT: 0 -- no blanks. Hypothesis rejected; the culprit is
-- something else. Step 6b widens the hunt.
-- ============================================================

--SELECT the count of rows (display)
--FROM the chart_entries table (pull from)
--WHERE the last_week value is empty text
--  OR the peak_pos value is empty text (either one qualifies the row)
SELECT COUNT(*)
FROM chart_entries
WHERE last_week = ''
   OR peak_pos = '';

-- ============================================================
-- STEP 6b: WHAT NON-NUMERIC VALUES ARE HIDING IN THESE COLUMNS?
-- WHY: Step 6 ruled out empty text, but the importer still saw
-- SOMETHING non-numeric in last_week and peak_pos. This query
-- stops guessing and asks directly: show every distinct value
-- in either column that contains ANY character that is not a
-- digit 0-9 (letters, dots, minus signs, stray spaces -- all of
-- them would force a column to import as TEXT).
-- RESULT: last_week holds the text 'NA' (the R language's
-- "not available" marker; the source repo's pipeline is R). One
-- text value forces a whole column to TEXT. But the earlier peek
-- ALSO showed a debut with last_week = 0, so "no previous week"
-- may be marked two different ways -- and peak_pos showed no
-- non-numeric values here, leaving its TEXT type unexplained.
-- Step 6c counts everything.
-- ============================================================

--SELECT each different combination of the two suspect values (display)
--  * DISTINCT  collapse duplicates so each odd value shows once
--FROM the chart_entries table (pull from)
--WHERE the last_week value contains any non-digit character
--  OR the peak_pos value contains any non-digit character
--  * GLOB '*[^0-9]*'  a pattern test: * = anything, [^0-9] = one
--    character that is NOT a digit; so "anything, then a
--    non-digit, then anything" = flags any value that isn't
--    purely digits
--LIMIT only show the first 20 distinct offenders
SELECT DISTINCT last_week, peak_pos
FROM chart_entries
WHERE last_week GLOB '*[^0-9]*'
   OR peak_pos GLOB '*[^0-9]*'
LIMIT 20;

-- ============================================================
-- STEP 6c: HOW BIG IS EACH ODDITY?
-- WHY: knowing WHAT the odd values are isn't enough -- their
-- COUNTS decide how they get handled. A handful of odd rows can
-- be documented and stepped around; hundreds of thousands mean
-- the oddity IS the data and every later query must speak its
-- language. This also settles whether peak_pos truly has any
-- non-numeric rows or imported as TEXT for another reason.
-- TRICK USED: a comparison like (last_week = 'NA') returns 1
-- when true and 0 when false, so SUM of a comparison = how many
-- rows passed the test. Three counts, one pass over the table.
-- RESULT: 354,500 total. last_week = 'NA' on 32,460 rows and
-- = '0' on 3,744 rows -- the file really does mark "no previous
-- week" two different ways, consistent with an archive stitched
-- from different eras. Every later query treating debuts must
-- accept BOTH markers. peak_pos: zero non-numeric values, so its
-- TEXT type is still unexplained -- next suspect is leading
-- zeros (all digits, but numeric conversion would not survive a
-- round trip). Step 6d tests that.
-- ============================================================

--SELECT four numbers side by side (display)
--  * COUNT(*)  every row in the table
--  * SUM(last_week = 'NA')  how many rows mark no-prior-week as NA
--  * SUM(last_week = '0')   how many rows mark it as 0 instead
--  * SUM(peak_pos GLOB '*[^0-9]*')  how many peak_pos values
--    contain any non-digit character at all
--FROM the chart_entries table (pull from)
SELECT COUNT(*) AS total_rows,
       SUM(last_week = 'NA') AS na_last_week,
       SUM(last_week = '0') AS zero_last_week,
       SUM(peak_pos GLOB '*[^0-9]*') AS weird_peak_pos
FROM chart_entries;

-- ============================================================
-- STEP 6d: DOES peak_pos HIDE LEADING ZEROS?
-- WHY: every peak_pos is pure digits yet the column imported as
-- TEXT. A value like '07' explains that: all digits, but not in
-- canonical number form. THE ROUND-TRIP TEST: convert the text
-- to a number and back to text; a canonical value ('7') survives
-- unchanged, a leading-zero value ('07' -> 7 -> '7') does not.
-- Any value that fails the round trip is shown with its count.
-- RESULT: empty -- zero leading zeros, zero non-canonical
-- values. peak_pos is clean digit text throughout; the importer
-- typed it TEXT out of pure caution. Conclusion for the whole
-- file: declared column types are hints, not guarantees. Verify
-- them, then CAST explicitly wherever these columns meet math.
-- ============================================================

--SELECT each offending value and how often it occurs (display)
--  * peak_pos  the original stored text
--  * COUNT(*)  how many rows hold that exact value
--FROM the chart_entries table (pull from)
--WHERE the value does not survive text -> number -> text
--  * CAST(peak_pos AS INTEGER)  text to number ('07' becomes 7)
--  * CAST(... AS TEXT)          number back to text (7 becomes '7')
--  * != peak_pos                keep only values that came back
--    different from how they started
--GROUP BY each distinct offending value, one result row per value
SELECT peak_pos,
       COUNT(*) AS rows_with_value
FROM chart_entries
WHERE CAST(CAST(peak_pos AS INTEGER) AS TEXT) != peak_pos
GROUP BY peak_pos;

-- ============================================================
-- STEP 7: WHICH ARTISTS HAS THE CHART SEEN MOST?
-- WHY: the project's definition of a "known artist" is an artist
-- the Hot 100 has charted multiple times -- radio demonstrably
-- knows them. Before picking the threshold for "multiple times"
-- (set from the data, never guessed), look at the top of the
-- distribution: who charts the most DISTINCT songs, and what do
-- those numbers look like? This collapses 354,500 week-rows into
-- one row per performer, the first step toward a proper artists
-- table.
-- RESULT: Taylor Swift 247, Drake 185, Glee Cast 183, then a
-- long tail (Beatles 66, Beyonce 64, Aretha Franklin 64...).
-- Three warnings surfaced for later steps:
--   1. CREDIT FRAGMENTATION: "Elvis Presley With The Jordanaires"
--      (53) is one credit STRING, not all of Elvis -- artist
--      totals are split across credit variants. Step 8 measures
--      this before any artist table is built.
--   2. Glee Cast (183) charted weekly TV covers -- high chart
--      presence without being a radio-pushed recording artist.
--   3. Streaming-era inflation: since charts began counting
--      streams, a big album drop can chart 20+ tracks at once,
--      inflating modern artists' song counts vs older eras.
-- ============================================================

--SELECT each performer and how many different songs they charted (display)
--  * performer  the artist credit exactly as the chart printed it
--  * COUNT(DISTINCT title)  each song counted once, no matter how
--    many weeks it stayed on the chart
--FROM the chart_entries table (pull from)
--GROUP BY performer, collapsing all their week-rows into one row
--ORDER BY the song count, biggest first (DESC)
--LIMIT only show the top 25
SELECT performer,
       COUNT(DISTINCT title) AS songs_charted
FROM chart_entries
GROUP BY performer
ORDER BY songs_charted DESC
LIMIT 25;

-- ============================================================
-- STEP 8: HOW FRAGMENTED ARE ARTIST CREDITS? (Elvis test case)
-- WHY: Step 7 showed "Elvis Presley With The Jordanaires" as its
-- own row, which means one real-world artist is split across
-- several credit strings. How several? This query pulls every
-- distinct credit containing "Elvis Presley" with its song
-- count. The answer decides how the artists table must be built:
-- if fragmentation is mild, exact credits work; if it's heavy,
-- the build needs normalization rules, and either way the
-- decision comes from measurement, not assumption.
-- RESULT: SEVEN credit strings for one man. The top two split
-- his catalog nearly in half (With The Jordanaires 53, plain 50),
-- so counting by exact credit undercounts him by ~half. The
-- small fragments carry their own inconsistencies ("Carole
-- Lombard Quartet" vs "Carol Lombard Trio") and a 2002 remix
-- credit ("Elvis Presley vs JXL"). This is the classic ENTITY
-- RESOLUTION problem: many representations, one real entity.
-- Verdict: normalization rules are mandatory for the artists
-- table. Step 8b measures how much of the WHOLE table carries
-- multi-artist credit patterns before those rules get designed.
-- ============================================================

--SELECT each credit variant and its song count (display)
--  * performer  the credit string exactly as printed
--  * COUNT(DISTINCT title)  different songs under that credit
--FROM the chart_entries table (pull from)
--WHERE the credit contains the text "Elvis Presley" anywhere
--  * LIKE '%Elvis Presley%'  fuzzy text test; % = anything before
--    or after, so any credit mentioning him qualifies
--GROUP BY each distinct credit string, one result row per variant
--ORDER BY the song count, biggest first (DESC)
SELECT performer,
       COUNT(DISTINCT title) AS songs_charted
FROM chart_entries
WHERE performer LIKE '%Elvis Presley%'
GROUP BY performer
ORDER BY songs_charted DESC;

-- ============================================================
-- STEP 8b: HOW MANY CREDITS CONTAIN JOINER WORDS?
-- WHY: Elvis proved fragmentation exists; this measures its
-- scale. Credit strings combine artists with a handful of
-- recurring joiner patterns ("Featuring", "With", "&"). Counting
-- how many DISTINCT credits contain each pattern sizes the
-- problem: a few hundred means edge-case cleanup, tens of
-- thousands means joiner-handling is a core design requirement
-- for the artists table.
-- NEW TOOL: the FROM here reads from a SUBQUERY -- a query in
-- parentheses used as if it were a table. The inner query builds
-- the list of distinct credits; the outer query counts patterns
-- within that list, so each credit is counted once no matter how
-- many weeks it charted.
-- The three patterns weren't guessed: they are the joiners that
-- appeared in real rows in Steps 7 and 8. The spaces around each
-- pattern are deliberate (' With ' can't false-match "Withers").
-- RESULT: 11,275 distinct credits. "Featuring" in 2,662, "With"
-- in 244, "&" in 1,994 -- up to ~43% of credits carry a joiner,
-- so joiner-handling is a CORE design requirement, not cleanup.
-- Caution flag on "&": it also lives inside permanent band names
-- (duos like "Hall & Oates"), so splitting on it blindly would
-- shred real bands into fake artists. Step 8c looks at the top
-- "&" credits to size that false-positive risk before any
-- splitting rule is written.
-- ============================================================

--SELECT four counts side by side (display)
--  * COUNT(*)  every distinct credit string
--  * SUM(performer LIKE '% Featuring %')  credits with "Featuring"
--  * SUM(performer LIKE '% With %')       credits with "With"
--  * SUM(performer LIKE '% & %')          credits with "&"
--FROM a subquery: the list of distinct performer credits
SELECT COUNT(*) AS all_credits,
       SUM(performer LIKE '% Featuring %') AS featuring_credits,
       SUM(performer LIKE '% With %') AS with_credits,
       SUM(performer LIKE '% & %') AS amp_credits
FROM (SELECT DISTINCT performer FROM chart_entries);

-- ============================================================
-- STEP 8c: WHAT DOES "&" ACTUALLY JOIN? (false-positive check)
-- WHY: 1,994 credits contain "&". If they are mostly temporary
-- collaborations ("Drake & Future"), splitting on "&" is safe
-- and correct. If many are permanent band names ("Hall & Oates",
-- "Earth, Wind & Fire"), splitting would invent artists that
-- don't exist. Before writing any splitting rule, look at the
-- highest-volume "&" credits, where a wrong rule would do the
-- most damage.
-- RESULT: the top 25 is dominated by PERMANENT band/duo names
-- (Kool & The Gang 32, Earth, Wind & Fire 30, Jan & Dean 24,
-- Simon & Garfunkel 17...) with only a few temporary collabs
-- (Future & Metro Boomin 20, Lil Baby & Lil Durk 12). DESIGN
-- DECISION: do NOT split on "&" -- false positives dominate.
-- "&" credits keep their identity as-is; the cost (a duo's
-- member won't merge with their solo career) is documented as a
-- limitation. "Featuring" and "With" WILL be normalized, because
-- the text before them is reliably the primary artist.
-- ============================================================

--SELECT each "&" credit and its song count (display)
--  * performer  the credit string exactly as printed
--  * COUNT(DISTINCT title)  different songs under that credit
--FROM the chart_entries table (pull from)
--WHERE the credit contains "&" with spaces around it
--GROUP BY each distinct credit string, one result row per credit
--ORDER BY the song count, biggest first (DESC)
--LIMIT only show the top 25
SELECT performer,
       COUNT(DISTINCT title) AS songs_charted
FROM chart_entries
WHERE performer LIKE '% & %'
GROUP BY performer
ORDER BY songs_charted DESC
LIMIT 25;

-- ============================================================
-- STEP 9: PREVIEW THE PRIMARY-ARTIST RULE (no tables built yet)
-- WHY: the rule -- "the primary artist is the text before
-- ' Featuring ' or ' With '" -- sounds right, but rules get
-- proven on real rows before anything is built from them.
-- This query shows the original credit next to what the rule
-- would extract, on a sample of the credits the rule would
-- change. Reading the two columns side by side is the test:
-- every extracted value should be a clean, real artist name.
-- HOW THE EXTRACTION READS: if the credit contains
-- ' Featuring ', cut from position 1 to just before it; else if
-- it contains ' With ', same idea; else keep the credit whole.
-- RESULT: extraction clean across the sample ('N Sync, 112,
-- 2 Chainz, 21 Savage & Metro Boomin all correct) EXCEPT one
-- defect: "2Pac Duet With Mopreme" -> "2Pac Duet". The credit
-- joins with ' Duet With ' and the rule only knew ' With '.
-- Fixed in Step 9b.
-- ============================================================

--SELECT the original and the extraction side by side (display)
--  * performer  the credit exactly as printed
--  * CASE: when ' Featuring ' appears, SUBSTR cuts from position
--    1 for (position of ' Featuring ' minus 1) characters, i.e.
--    everything before it; when ' With ' appears, the same cut
--    before ' With '; otherwise the credit unchanged
--FROM the distinct credits (subquery, each credit once)
--WHERE only credits containing ' Featuring ' or ' With ' (the
--  rows the rule would actually change)
--ORDER BY performer alphabetically, stable and easy to scan
--LIMIT only show 30
SELECT performer,
       CASE
         WHEN INSTR(performer, ' Featuring ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Featuring ') - 1)
         WHEN INSTR(performer, ' With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' With ') - 1)
         ELSE performer
       END AS primary_artist
FROM (SELECT DISTINCT performer FROM chart_entries)
WHERE performer LIKE '% Featuring %'
   OR performer LIKE '% With %'
ORDER BY performer
LIMIT 30;

-- ============================================================
-- STEP 9b: FIX THE RULE AND RE-PREVIEW
-- WHY: the Step 9 preview caught one defect: "2Pac Duet With
-- Mopreme" extracted as "2Pac Duet", because the credit joins
-- with ' Duet With ' and the rule only knew ' With '. The fix
-- adds a ' Duet With ' branch ABOVE the ' With ' branch -- in a
-- CASE the first matching WHEN wins, so specific patterns must
-- be tested before the general patterns they contain. The re-run
-- checks the fix and rescans for anything else the first sample
-- didn't surface (this preview scans a different slice: ordered
-- by the EXTRACTED name instead of the original, so different
-- rows get eyeballed).
-- RESULT: extraction clean across the new slice, including hard
-- cases: lowercase artists (j-hope, fun., deadmau5, gnash),
-- "¥$:" prefix credits, and "&" credits kept whole per Step 8c
-- (benny blanco & Juice WRLD). One entity-resolution nugget for
-- the limitations list: the same duo appears as "¥$: Ye & Ty
-- Dolla $ign" AND "¥$: Kanye West & Ty Dolla $ign" -- one act,
-- two aliases; no alias dictionary is built for one act. This
-- slice never displayed a 'Duet With' row, so Step 9c confirms
-- the fix on its exact targets.
-- ============================================================

--SELECT the original and the extraction side by side (display)
--  * performer  the credit exactly as printed
--  * CASE, most-specific pattern first: cut before ' Duet With '
--    if present; else cut before ' Featuring '; else cut before
--    ' With '; else keep the credit whole
--FROM the distinct credits (subquery, each credit once)
--WHERE only credits containing a pattern the rule changes
--ORDER BY the extracted primary_artist name, scanning a
--  different slice of the alphabet than the first preview
--LIMIT only show 30
SELECT performer,
       CASE
         WHEN INSTR(performer, ' Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Duet With ') - 1)
         WHEN INSTR(performer, ' Featuring ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Featuring ') - 1)
         WHEN INSTR(performer, ' With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' With ') - 1)
         ELSE performer
       END AS primary_artist
FROM (SELECT DISTINCT performer FROM chart_entries)
WHERE performer LIKE '% Featuring %'
   OR performer LIKE '% With %'
ORDER BY primary_artist DESC
LIMIT 30;

-- ============================================================
-- STEP 9c: CONFIRM THE 'Duet With' FIX DIRECTLY
-- WHY: the 9b re-preview scanned a different alphabet slice and
-- never displayed the row the fix was written for. A fix is
-- confirmed by looking at the exact rows it targets, so this
-- filters to every credit containing 'Duet With' and shows what
-- the rule now extracts from each.
-- RESULT: "2Pac" extracts clean -- fix confirmed. And the
-- targeted check caught one MORE defect: "Patti Austin A Duet
-- With James Ingram" -> "Patti Austin A" (that credit joins with
-- ' A Duet With '). Same lesson one level deeper; fixed in 9d.
-- ============================================================

--SELECT the original and the extraction side by side (display)
--  * performer  the credit exactly as printed
--  * CASE, most-specific pattern first: cut before ' Duet With ',
--    else before ' Featuring ', else before ' With ', else keep
--    the credit whole
--FROM the distinct credits (subquery, each credit once)
--WHERE only credits containing 'Duet With' -- the fix's targets
--ORDER BY performer alphabetically
SELECT performer,
       CASE
         WHEN INSTR(performer, ' Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Duet With ') - 1)
         WHEN INSTR(performer, ' Featuring ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Featuring ') - 1)
         WHEN INSTR(performer, ' With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' With ') - 1)
         ELSE performer
       END AS primary_artist
FROM (SELECT DISTINCT performer FROM chart_entries)
WHERE performer LIKE '% Duet With %'
ORDER BY performer;

-- ============================================================
-- STEP 9d: HANDLE 'A Duet With', CONFIRM THE LADDER IS DONE
-- WHY: the 9c check caught "Patti Austin A Duet With James
-- Ingram" extracting as "Patti Austin A" -- that credit joins
-- with ' A Duet With '. The fix follows the established rule:
-- each MORE specific pattern sits ABOVE the general pattern it
-- contains, so the CASE ladder is now A-Duet-With, Duet-With,
-- Featuring, With. The re-run repeats the targeted check on all
-- 'Duet With' credits; every extraction reading clean means the
-- ladder is complete for the patterns this table contains.
-- This is genuinely how normalization rules get built in
-- practice: preview on real rows, catch an exception, add a
-- rung, re-check -- iterate until the exceptions stop appearing.
-- RESULT: every extraction clean, "Patti Austin" included.
-- Ladder complete. This CASE expression is now the project's
-- official primary-artist rule, ready to build the artists
-- table from.
-- ============================================================

--SELECT the original and the extraction side by side (display)
--  * performer  the credit exactly as printed
--  * CASE, most-specific pattern first: cut before ' A Duet
--    With ', else before ' Duet With ', else before
--    ' Featuring ', else before ' With ', else keep whole
--FROM the distinct credits (subquery, each credit once)
--WHERE only credits containing 'Duet With' -- the fix's targets
--ORDER BY performer alphabetically
SELECT performer,
       CASE
         WHEN INSTR(performer, ' A Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' A Duet With ') - 1)
         WHEN INSTR(performer, ' Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Duet With ') - 1)
         WHEN INSTR(performer, ' Featuring ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Featuring ') - 1)
         WHEN INSTR(performer, ' With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' With ') - 1)
         ELSE performer
       END AS primary_artist
FROM (SELECT DISTINCT performer FROM chart_entries)
WHERE performer LIKE '% Duet With %'
ORDER BY performer;

-- ============================================================
-- STEP 10: BUILD artist_songs -- ONE ROW PER SONG, NORMALIZED
-- WHY: the raw table is one row per WEEK (354,500). The analysis
-- needs one row per SONG, labeled with its normalized primary
-- artist (the Step 9d rule) and its chart achievements. CREATE
-- TABLE ... AS runs a query once and SAVES the result as a real
-- table, so the CASE ladder never has to be repeated again --
-- every later step just reads the clean table.
-- WHAT EACH SONG KEEPS:
--   best_peak   the highest position ever reached; positions
--               count DOWN (1 = the top), so best = MIN. peak_pos
--               is TEXT (Step 6d), so it is CAST before MIN.
--   total_weeks the most weeks-on-chart ever shown for the song.
-- GROUP BY primary_artist AND title: the same title by two
-- different artists (covers) stays two separate songs.
-- After running: Write Changes (Ctrl+S) -- a created table only
-- becomes permanent when the database file is saved.
-- RESULT: table built; Step 11 verified 32,631 song rows across
-- 8,896 distinct primary artists.
-- ============================================================

--CREATE TABLE artist_songs AS: save this query's result as a new table
--SELECT for each song (display -> stored columns)
--  * the normalized primary artist: the Step 9d CASE ladder,
--    most-specific pattern first (' A Duet With ', ' Duet With ',
--    ' Featuring ', ' With '), else the credit kept whole
--  * performer  the original credit, kept for traceability
--  * title      the song's name
--  * MIN of peak_pos CAST to a number, AS best_peak (1 = best)
--  * MAX of wks_on_chart, AS total_weeks
--FROM the chart_entries table (pull from)
--GROUP BY the normalized artist and the title, collapsing all of
--  a song's week-rows into one row
CREATE TABLE artist_songs AS
SELECT CASE
         WHEN INSTR(performer, ' A Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' A Duet With ') - 1)
         WHEN INSTR(performer, ' Duet With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Duet With ') - 1)
         WHEN INSTR(performer, ' Featuring ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' Featuring ') - 1)
         WHEN INSTR(performer, ' With ') > 0
           THEN SUBSTR(performer, 1, INSTR(performer, ' With ') - 1)
         ELSE performer
       END AS primary_artist,
       performer,
       title,
       MIN(CAST(peak_pos AS INTEGER)) AS best_peak,
       MAX(wks_on_chart) AS total_weeks
FROM chart_entries
GROUP BY primary_artist, title;

-- ============================================================
-- STEP 11: HOW MANY SONGS AND ARTISTS DID THE BUILD PRODUCE?
-- WHY: a created table gets the same treatment as an imported
-- one -- verify before trust. Two counts tell the story: total
-- song rows (the new grain: one row per artist+title), and
-- distinct primary artists. Expectations from earlier steps:
-- song rows somewhere near the count of distinct performer+title
-- pairs, and primary artists BELOW the 11,275 raw credit strings
-- -- normalization exists to merge credit variants, so a number
-- that didn't shrink would mean the rule changed nothing.
-- RESULT: 32,631 songs, 8,896 artists. The artist count shrank
-- from 11,275 raw credits to 8,896 normalized artists -- the
-- CASE ladder merged 2,379 credit variants (21%) into their
-- primary artists. Both numbers entered in the shrink ledger.
-- ============================================================

--SELECT two counts side by side (display)
--  * COUNT(*)  one per song row (artist+title pair)
--  * COUNT(DISTINCT primary_artist)  how many normalized artists
--FROM the artist_songs table (pull from)
SELECT COUNT(*) AS songs,
       COUNT(DISTINCT primary_artist) AS artists
FROM artist_songs;

-- ============================================================
-- STEP 12: HOW MANY SONGS DOES A TYPICAL CHARTING ARTIST HAVE?
-- WHY: the project defines a "known artist" as one the chart
-- has seen multiple times -- but "multiple" needs a number, and
-- that number comes from the distribution, not from a guess.
-- This query builds the distribution: for each song-count (1
-- song, 2 songs, 3...), how many artists have exactly that many
-- charted songs? Reading it shows where the natural break sits
-- between one-visit artists and artists radio genuinely knows.
-- TWO LAYERS: the inner subquery counts songs per artist; the
-- outer query then groups ARTISTS by that count -- a GROUP BY
-- on top of a GROUP BY, which is how "distribution of a count"
-- is always built.
-- RESULT: the chart is mostly brief visitors -- 57% of all
-- artists charted exactly ONE song (one-hit wonders), and the
-- counts fall off steeply from there. "Known" therefore sits
-- well above 1; Step 13 prices the candidate cutoffs.
-- ============================================================

--SELECT each song-count and how many artists sit at it (display)
--  * songs_charted  how many songs an artist charted
--  * COUNT(*)       how many artists have exactly that many
--FROM a subquery: one row per artist with their song count
--  (inner: SELECT the artist and COUNT their rows in
--   artist_songs, GROUP BY artist)
--GROUP BY the song-count, one result row per distinct count
--ORDER BY the song-count, smallest first
--LIMIT only show the first 20 counts
SELECT songs_charted,
       COUNT(*) AS artists_with_this_many
FROM (SELECT primary_artist,
             COUNT(*) AS songs_charted
      FROM artist_songs
      GROUP BY primary_artist)
GROUP BY songs_charted
ORDER BY songs_charted
LIMIT 20;

-- ============================================================
-- STEP 13: HOW MANY ARTISTS SURVIVE EACH CANDIDATE THRESHOLD?
-- WHY: the distribution ruled out one-song artists; now the
-- cutoff for "known" gets chosen from measured options, not
-- gut feel. Three candidates, each with a defensible reading:
--   >= 3   radio came back at least twice after the debut
--   >= 5   radio returned repeatedly across a career
--   >= 10  a chart fixture
-- One practical stake: the next phase calls the Last.fm API
-- once per known artist, so this count is also the size of
-- that data pull.
-- RESULT: >=3 keeps 2,596 artists, >=5 keeps 1,570, >=10 keeps
-- 740. DECISION: >= 5 -- strict enough that radio demonstrably
-- returned to the artist across a career, big enough to leave a
-- wide gem-hunting ground, and a 1,570-call API pull is
-- comfortably polite. Chosen from the measured distribution.
-- ============================================================

--SELECT three survivor-counts side by side (display)
--  * SUM(songs_charted >= 3)   artists with three or more songs
--  * SUM(songs_charted >= 5)   artists with five or more
--  * SUM(songs_charted >= 10)  artists with ten or more
--  (a comparison returns 1/0, so SUM counts the artists passing)
--FROM a subquery: one row per artist with their song count
SELECT SUM(songs_charted >= 3) AS at_least_3,
       SUM(songs_charted >= 5) AS at_least_5,
       SUM(songs_charted >= 10) AS at_least_10
FROM (SELECT primary_artist,
             COUNT(*) AS songs_charted
      FROM artist_songs
      GROUP BY primary_artist);

-- ============================================================
-- STEP 14: BUILD known_artists -- THE PROJECT'S ARTIST ROSTER
-- WHY: the threshold chosen from the Step 12-13 distribution
-- (5+ charted songs; 1,570 artists survive vs 2,596 at 3+ and
-- 740 at 10+) now becomes a real table, so every later step
-- can join against the roster instead of re-deriving it. This
-- roster also defines the upcoming Last.fm data pull: one API
-- call per known artist.
-- NEW TOOL -- HAVING: WHERE filters ROWS before grouping, so it
-- can't see group totals; HAVING filters the GROUPS after they
-- are built, which is what a "5 or more songs" test needs.
-- After running: Write Changes (Ctrl+S) to make it permanent.
-- RESULT: table built; Step 15 verified 1,570 roster rows.
-- ============================================================

--CREATE TABLE known_artists AS: save this query's result as a new table
--SELECT for each artist (display -> stored columns)
--  * primary_artist  the normalized artist name
--  * COUNT(*) AS songs_charted     how many songs they charted
--  * MIN(best_peak) AS career_peak the best chart position any
--    of their songs ever reached (1 = topped the chart)
--FROM the artist_songs table (pull from)
--GROUP BY the artist, collapsing their songs into one roster row
--HAVING keep only groups with 5 or more songs (the threshold)
CREATE TABLE known_artists AS
SELECT primary_artist,
       COUNT(*) AS songs_charted,
       MIN(best_peak) AS career_peak
FROM artist_songs
GROUP BY primary_artist
HAVING COUNT(*) >= 5;

-- ============================================================
-- STEP 15: VERIFY THE ROSTER
-- WHY: "the CREATE ran" and "it built the right thing" are two
-- different facts. Two checks settle it: the row count must
-- equal the number Step 13 measured for the 5+ threshold
-- (1,570 -- the same filter expressed two different ways must
-- agree), and a peek at the top of the roster must show famous
-- names with sane song counts and career peaks (a career_peak
-- of 1 means the artist topped the chart at least once).
-- RESULT: roster_size = 1,570, exactly matching the Step 13
-- measurement -- the same filter expressed two ways agrees, so
-- the roster is trusted. The top-of-roster eyeball showed the
-- expected heavyweights with sane song counts and career peaks.
-- Chart side COMPLETE: chart_entries (raw weeks), artist_songs
-- (one row per song), known_artists (the roster). Next: the
-- Last.fm side, fetched by scripts/fetch_lastfm.py.
-- ============================================================

--SELECT the roster size (display)
--FROM the known_artists table (pull from)
SELECT COUNT(*) AS roster_size
FROM known_artists;

--SELECT the roster's biggest names to eyeball (display)
--  * primary_artist, songs_charted, career_peak
--FROM the known_artists table (pull from)
--ORDER BY songs charted, biggest first (DESC)
--LIMIT only show the top 15
SELECT primary_artist,
       songs_charted,
       career_peak
FROM known_artists
ORDER BY songs_charted DESC
LIMIT 15;

-- ============================================================
-- STEP 16-17: FETCH THE LAST.FM DATA (Python, outside this file)
-- WHY: SQL cannot call the internet, so the listener data is
-- collected by scripts/fetch_lastfm.py -- read its comments the
-- same way as this file's. It reads the API key from
-- lastfm_api_key.txt (never typed into code; the file is
-- gitignored), pulls the 1,570-artist roster straight from
-- known_artists in this database, calls the artist.gettoptracks
-- endpoint once per artist (top 50 tracks each, one request per
-- quarter second -- polite rate limiting), and writes a DATED
-- CSV: Last.fm numbers change daily, so the filename records
-- when the snapshot was taken.
-- ALWAYS TEST FIRST: "py scripts\fetch_lastfm.py 3" runs just 3
-- artists in ~5 seconds and proves the key and URL work before
-- committing to the ~25-minute full run ("py scripts\
-- fetch_lastfm.py" with no number).
-- RESULT: full run 2026-07-14 -- 78,335 tracks from all 1,570
-- artists, 0 failures, written to
-- data/lastfm_tracks_2026-07-14.csv. (1,570 x 50 would be
-- 78,500; the gap of 165 is small acts with fewer than 50
-- tracks on Last.fm -- reality below the ceiling, not loss.)
-- The CSV was imported as table lastfm_tracks with every dialog
-- field set explicitly (table name lastfm_tracks, first-line
-- column names CHECKED, separator comma, quote ", UTF-8), then
-- Write Changes.
-- ============================================================

-- ============================================================
-- STEP 18: VERIFY THE lastfm_tracks IMPORT
-- WHY: the fetch script reported 78,335 tracks from 1,570
-- artists, and the CSV was verified to hold exactly that. The
-- imported table must agree with both numbers -- the same data
-- counted at three checkpoints (script output, file, table)
-- must tell one story, or something got lost in a handoff. The
-- peek then checks the columns landed where the header says,
-- including the quote-heavy '"Weird Al" Yankovic'. Also check
-- the TYPES in Database Structure: playcount and listeners
-- imported INTEGER (clean machine-made API data), so no CAST
-- is needed for their math -- unlike peak_pos on the chart side.
-- RESULT: 78,335 tracks, 1,570 artists -- exact match at every
-- checkpoint. Peek clean. One discovery for later: the peek
-- showed "Amish Paradise (Parody of ...)" AND plain "Amish
-- Paradise" as separate tracks -- one real song fragmented
-- across name variants. Entity resolution, track edition
-- (docs/DATA_QUALITY.md Issue 6); handled at the join steps.
-- ============================================================

--SELECT two counts side by side (display)
--  * COUNT(*)  every track row imported
--  * COUNT(DISTINCT artist)  how many different artists
--FROM the lastfm_tracks table (pull from)
SELECT COUNT(*) AS tracks,
       COUNT(DISTINCT artist) AS artists
FROM lastfm_tracks;

--SELECT every column (* = all of them)
--FROM the lastfm_tracks table (pull from)
--LIMIT only show the first 20 rows
SELECT *
FROM lastfm_tracks
LIMIT 20;

-- ============================================================
-- STEP 19: HOW MANY LAST.FM TITLES CARRY A PARENTHETICAL TAIL?
-- WHY: the Step 18 peek showed one real song split across name
-- variants differing by a parenthetical suffix. The gem query
-- will join chart titles to Last.fm titles by text, so every
-- variant is a potential missed match. Before designing any
-- cleaning rule, measure the pattern's scale.
-- RESULT: 8,675 of 78,335 tracks (11%) contain an opening
-- parenthesis -- core-requirement territory, but the number
-- alone doesn't say what to do. Step 19b reads the rows.
-- ============================================================

--SELECT two counts side by side (display)
--  * COUNT(*)  every track row
--  * SUM(track LIKE '%(%')  rows whose title contains an opening
--    parenthesis (a comparison returns 1/0, so SUM counts them)
--FROM the lastfm_tracks table (pull from)
SELECT COUNT(*) AS all_tracks,
       SUM(track LIKE '%(%') AS tracks_with_parens
FROM lastfm_tracks;

-- ============================================================
-- STEP 19b: WHAT DO THE PARENTHESES ACTUALLY CONTAIN?
-- WHY: 8,675 titles carry a parenthesis, but a cleaning rule
-- can only be designed after seeing what kinds there are. If
-- the tails are mostly annotations they are safe to trim for
-- matching; if many are part of the song's real name, trimming
-- would mangle true titles. Eyeballing the highest-listener
-- parenthetical tracks reads the rule's targets where a wrong
-- rule would do the most damage -- the same false-positive
-- check the "&" credits got in Step 8c.
-- RESULT: two clear kinds. SAFE TO TRIM: credit tags --
-- "(feat. Kali Uchis)", "(with SZA)" -- bolted on by music
-- players; chart titles never carry them (credits live in
-- performer there). MUST KEEP: real-name parentheses -- "Last
-- Friday Night (T.G.I.F.)", "Single Ladies (Put a Ring on
-- It)", "P.Y.T. (Pretty Young Thing)" -- Billboard prints
-- those too. DESIGN DECISION: trim ONLY tails beginning with
-- '(feat.' or '(with '; blanket paren-stripping is dead, killed
-- by the same eyeball test that killed "&"-splitting.
-- BONUS CATCH: "Tyler, The Creator" and "Tyler, the Creator"
-- appeared as separate rows with identical tracks -- both
-- capitalizations exist in the roster (the chart printed him
-- both ways), so his tracks were fetched twice. Step 20
-- measures that.
-- ============================================================

--SELECT the artist, the full title, and its listener count (display)
--FROM the lastfm_tracks table (pull from)
--WHERE the title contains an opening parenthesis
--ORDER BY listeners, biggest first (DESC) -- the popular rows,
--  where a wrong cleaning rule costs the most matches
--LIMIT only show the top 30
SELECT artist,
       track,
       listeners
FROM lastfm_tracks
WHERE track LIKE '%(%'
ORDER BY listeners DESC
LIMIT 30;

-- ============================================================
-- STEP 19c: HOW MUCH DO THE SAFE-TRIM PATTERNS COVER?
-- WHY: the rule "trim only (feat. and (with tails" is only
-- worth writing if it covers a meaningful share of the 8,675
-- parenthetical titles. This counts each pattern's share.
-- LOWER() makes the test catch (Feat., (FEAT., and (feat. alike
-- -- crowd-typed data guarantees mixed capitalization.
-- RESULT: 2,442 feat-tails + 401 with-tails = 2,843 of 8,675
-- (about a third). The other two thirds are real-name parens
-- plus other annotation types. The conservative rule ships;
-- the match rate will say whether more rungs are worth it --
-- evidence-driven iteration, same as the CASE ladder.
-- ============================================================

--SELECT three counts side by side (display)
--  * SUM over titles containing '(feat.'  credit tags, feat form
--  * SUM over titles containing '(with '  credit tags, with form
--  * COUNT(*)  all parenthetical titles, for the denominator
--FROM the lastfm_tracks table (pull from)
--WHERE only titles containing an opening parenthesis
SELECT SUM(LOWER(track) LIKE '%(feat.%') AS feat_tails,
       SUM(LOWER(track) LIKE '%(with %') AS with_tails,
       COUNT(*) AS all_paren_titles
FROM lastfm_tracks
WHERE track LIKE '%(%';

-- ============================================================
-- STEP 20: HOW MANY ROSTER ARTISTS ARE CASE-VARIANT DUPLICATES?
-- WHY: Step 19b caught one artist under two capitalizations --
-- two roster rows, tracks fetched twice, and duplicated tracks
-- would double-count in the gem list. Before deciding a fix,
-- measure it: group the roster by its LOWERCASED name and keep
-- only groups with more than one row.
-- RESULT: exactly three real artists split by capitalization:
-- tyler, the creator / jay-z / charli xcx -- 6 roster rows for
-- 3 people, 0.2% of the roster. DECISION: no rebuild; every
-- text join uses LOWER() keys, which merges the case twins and
-- collapses their duplicate tracks in one move. 0.2% justified
-- a query-time fix; 20% would have justified rebuilding. The
-- measurement chose the remedy (DATA_QUALITY.md Issue 7).
-- ============================================================

--SELECT each lowercased name and how many roster rows share it (display)
--  * LOWER(primary_artist)  the name with capitalization removed
--  * COUNT(*)               how many roster rows collapse onto it
--FROM the known_artists table (pull from)
--GROUP BY the lowercased name, one row per distinct name
--HAVING keep only groups with more than one roster row
--ORDER BY the row count, biggest first (DESC)
SELECT LOWER(primary_artist) AS artist_lower,
       COUNT(*) AS roster_rows
FROM known_artists
GROUP BY LOWER(primary_artist)
HAVING COUNT(*) > 1
ORDER BY roster_rows DESC;

-- ============================================================
-- STEP 21: HOW ARE LISTENER COUNTS DISTRIBUTED?
-- WHY: the gem signal is playcount / listeners, and ratios lie
-- when the denominator is tiny -- a track 40 people played 30
-- times each posts a huge ratio that means nothing. A minimum-
-- listeners floor is needed, and like the roster's 5+ threshold
-- it gets chosen from the measured distribution. This first
-- look maps the terrain in power-of-ten bands.
-- RESULT: listeners run from 1 to 4,146,376. Bands: under 1k =
-- 13,507 (17% -- the noise floor the floor exists to fence
-- off), 1k-10k = 22,534, 10k-100k = 25,792, 100k-1M = 15,187,
-- 1M+ = 1,315. Bands sum to 78,335 -- all rows accounted for.
-- ============================================================

--SELECT seven numbers side by side (display)
--  * MIN(listeners) and MAX(listeners)  the full range
--  * five SUM(...) band counts (a comparison returns 1/0, so
--    SUM counts the band)
--FROM the lastfm_tracks table (pull from)
SELECT MIN(listeners) AS smallest,
       MAX(listeners) AS biggest,
       SUM(listeners < 1000) AS under_1k,
       SUM(listeners >= 1000 AND listeners < 10000) AS band_1k_10k,
       SUM(listeners >= 10000 AND listeners < 100000) AS band_10k_100k,
       SUM(listeners >= 100000 AND listeners < 1000000) AS band_100k_1m,
       SUM(listeners >= 1000000) AS band_1m_plus
FROM lastfm_tracks;

-- ============================================================
-- STEP 22: HOW MANY TRACKS SURVIVE EACH CANDIDATE FLOOR?
-- WHY: three candidate floors, each with a defensible reading:
--   >= 1,000    excludes only the noise floor
--   >= 5,000    a small but unmistakable audience
--   >= 10,000   a solid audience by any reading
-- The floor guards the RATIO, not the hiddenness -- hiddenness
-- is defined by chart absence, and buried songs have smaller
-- audiences by definition, so the floor should be as low as
-- ratio-safety allows.
-- RESULT: >=1k keeps 64,828 (83%), >=5k keeps 50,308, >=10k
-- keeps 42,294. DECISION: 1,000 -- a thousand people is plenty
-- to stabilize an average, and every notch higher discards
-- tracks in the exact obscurity zone this project hunts. Said
-- out loud: "at least a thousand real people found this song,
-- so how hard they replay it means something."
-- ============================================================

--SELECT three survivor-counts side by side (display)
--  (a comparison returns 1/0, so SUM counts the survivors)
--FROM the lastfm_tracks table (pull from)
SELECT SUM(listeners >= 1000) AS at_least_1k,
       SUM(listeners >= 5000) AS at_least_5k,
       SUM(listeners >= 10000) AS at_least_10k
FROM lastfm_tracks;

-- ============================================================
-- STEP 23: HOW IS PLAYS-PER-LISTENER DISTRIBUTED?
-- WHY: the second threshold: how many plays per listener counts
-- as "high" devotion? Same method: map the distribution first,
-- over the tracks passing the 1,000-listener floor. CAST to
-- REAL matters: both columns are INTEGER, and integer division
-- would silently floor 6.9 down to 6.
-- RESULT: of 64,828 floor-passing tracks -- under 2: 2,782;
-- 2-4: 34,074 (the typical band); 4-6: 14,882; 6-10: 9,146;
-- 10+: 3,944. The bands also price the candidates: >=4 keeps
-- 27,972 (43%, too generous to mean "loved"), >=6 keeps 13,090
-- (20%), >=10 keeps 3,944 (6%, obsessive tier). DECISION: 6+ --
-- clearly above the typical band ("listeners replay this
-- noticeably harder than a normal song by an artist they
-- know"), wide enough to hunt in; 10+ stays available as a
-- sort within the final list.
-- ============================================================

--SELECT six counts side by side (display)
--  (ratio = CAST(playcount AS REAL) / listeners in each test)
--FROM the lastfm_tracks table (pull from)
--WHERE only tracks clearing the 1,000-listener floor
SELECT SUM(CAST(playcount AS REAL) / listeners < 2) AS under_2,
       SUM(CAST(playcount AS REAL) / listeners >= 2 AND CAST(playcount AS REAL) / listeners < 4) AS band_2_4,
       SUM(CAST(playcount AS REAL) / listeners >= 4 AND CAST(playcount AS REAL) / listeners < 6) AS band_4_6,
       SUM(CAST(playcount AS REAL) / listeners >= 6 AND CAST(playcount AS REAL) / listeners < 10) AS band_6_10,
       SUM(CAST(playcount AS REAL) / listeners >= 10) AS band_10_plus,
       COUNT(*) AS floor_passing
FROM lastfm_tracks
WHERE listeners >= 1000;

-- ============================================================
-- STEP 24: BUILD THE KEYED TABLES (AND WHY, THE HARD WAY)
-- WHY: the gem query joins the two sides by artist + title
-- text. Joining on function-wrapped keys -- LOWER(...) around
-- both sides -- looks harmless and is a trap: the database
-- cannot use any index through the functions, so it recomputes
-- them for every row-pair. 13,090 devoted tracks x 32,631 chart
-- songs = ~427 million comparisons; the first attempt at this
-- join ran OVER 30 MINUTES and had to be killed from Task
-- Manager. The durable fix (and a real warehouse pattern):
-- compute each side's clean join key ONCE, store it as a real
-- column, index the plain column, and join column to column.
-- devoted_tracks = the 13,090 tracks passing both thresholds
-- (Steps 22-23), with artist_key (lowercased -- merges the
-- Step 20 case twins) and title_key (feat/with tails cut by
-- the Step 19 rules, trimmed, lowercased). song_keys = every
-- chart song with the same two keys (chart titles carry no
-- feat/with tails; credits live in performer there).
-- After running: Write Changes (Ctrl+S).
-- RESULT: both tables built; the match-rate queries that follow
-- return in SECONDS. Never ship a join on function-wrapped
-- keys; index the exact expression your joins search by, or
-- better, store it.
-- ============================================================

--DROP TABLE IF EXISTS: throw away any half-built copy, so this
--  whole step is safe to re-run from the top
DROP TABLE IF EXISTS devoted_tracks;
DROP TABLE IF EXISTS song_keys;

--CREATE TABLE devoted_tracks AS: save the filtered Last.fm side
--SELECT for each devoted track (stored columns)
--  * artist, track, playcount, listeners  carried as-is
--  * plays_per_listener  the devotion ratio, ROUNDed to 1 place
--  * artist_key  the artist lowercased
--  * title_key   the title with a feat/with tail cut off by the
--    CASE ladder (INSTR runs on the lowercased title so any
--    capitalization of (feat. is caught), TRIMmed, lowercased
--FROM the lastfm_tracks table (pull from)
--WHERE both thresholds pass (the 1,000-listener floor and the
--  6+ devotion cutoff; CAST keeps decimals)
CREATE TABLE devoted_tracks AS
SELECT artist,
       track,
       playcount,
       listeners,
       ROUND(CAST(playcount AS REAL) / listeners, 1) AS plays_per_listener,
       LOWER(artist) AS artist_key,
       LOWER(TRIM(CASE
         WHEN INSTR(LOWER(track), ' (feat.') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (feat.') - 1)
         WHEN INSTR(LOWER(track), ' (with ') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (with ') - 1)
         ELSE track
       END)) AS title_key
FROM lastfm_tracks
WHERE listeners >= 1000
  AND CAST(playcount AS REAL) / listeners >= 6;

--CREATE TABLE song_keys AS: save the chart side with its keys
--SELECT for each chart song (stored columns)
--  * primary_artist, title, best_peak, total_weeks  carried as-is
--  * artist_key, title_key  both simply lowercased
--FROM the artist_songs table (pull from)
CREATE TABLE song_keys AS
SELECT primary_artist,
       title,
       best_peak,
       total_weeks,
       LOWER(primary_artist) AS artist_key,
       LOWER(title) AS title_key
FROM artist_songs;

--CREATE INDEX: a plain-column lookup on song_keys over exactly
--  the two columns the join searches by -- no functions, so the
--  database can always use it
CREATE INDEX IF NOT EXISTS idx_song_keys ON song_keys (artist_key, title_key);

-- ============================================================
-- STEP 25: BASELINE MATCH RATE
-- WHY: with keyed tables built, measure the starting point: of
-- the devoted tracks, how many find a chart row for the same
-- artist and title? The unmatched share is EITHER a true gem
-- (never charted -- what the project hunts) OR a missed match
-- (charted under a different spelling -- a defect). Cleaning
-- rules get judged by how much they move this number; it is
-- NEVER supposed to reach 100%, because unmatched tracks are
-- the whole point.
-- JOIN MECHANICS (see docs/JOINS_GUIDE.md): ON is the PAIRING
-- rule (both keys must match -- a compound key; artist alone
-- would pair a song with every song by that artist, title alone
-- with every cover). LEFT JOIN keeps every devoted track even
-- with no partner (NULLs fill the chart side). WHERE is the
-- SURVIVAL rule and comes later. SUM(s.title IS NOT NULL)
-- counts the paired.
-- RESULT: 13,099 joined rows (13,090 devoted tracks + 9 fan-out
-- duplicates where lowercase matching collapsed two chart rows
-- onto one track -- noted, deduped at the gems build), 4,853
-- matched after the feat/with trims = 37.0%. (For the record:
-- lowercase-only keys with no feat/with trim measured 31.2%;
-- the trim recovered 763 real matches.)
-- ============================================================

--SELECT three numbers side by side (display)
--  * COUNT(*)  every devoted track (plus join fan-out)
--  * SUM(s.title IS NOT NULL)  tracks that found a chart row
--  * ROUND of matched * 100.0 / total, 1 decimal  the match rate
--FROM the devoted_tracks table AS t (pull from)
--LEFT JOIN song_keys AS s on both plain keys (index-served)
SELECT COUNT(*) AS devoted_tracks,
       SUM(s.title IS NOT NULL) AS matched_to_chart,
       ROUND(SUM(s.title IS NOT NULL) * 100.0 / COUNT(*), 1) AS match_rate_pct
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key;

-- ============================================================
-- STEP 26: CLERICAL REVIEW -- READ THE UNMATCHED
-- WHY: the unmatched 63% is the gem candidate pool PLUS any
-- remaining spelling casualties. Record linkage's classic
-- framework sends undecided records to human review; the
-- everyday version is simply reading the unmatched rows,
-- sorted so the most consequential come first. If the top is
-- full of songs that obviously DID chart, the rules have a
-- gap; if it reads like album cuts and deep catalog, matching
-- is done. HOW: the ANTI-JOIN -- LEFT JOIN, then WHERE the
-- right side IS NULL keeps only the tracks with no partner.
-- This is the exact shape of the final gem query.
-- RESULT: mostly GENUINE non-charters with a historical story:
-- until December 1998 Billboard required a commercially
-- released physical single to chart, and 90s alternative bands
-- didn't release them -- Everlong, Basket Case, Don't Speak
-- (famously the biggest airplay song of its year, never on the
-- Hot 100). A finding AND a limitation: pre-1999 "buried"
-- includes songs the chart's own rules excluded. Two NAMED
-- defects also caught: "Dreams - 2004 Remaster" (streaming-era
-- dash-suffix version tags -- Step 27 measures), and
-- "Summertime Sadness" (charted as a remix credited "Lana Del
-- Rey vs. Cedric Gervais" -- a ' vs. ' joiner the artist ladder
-- never met; one case in two eyeball passes = documented
-- residual, not another rebuild).
-- ============================================================

--SELECT the artist, title, and devotion stats of unmatched tracks (display)
--FROM the devoted_tracks table AS t (pull from)
--LEFT JOIN song_keys AS s on both keys, keeping every t row
--WHERE the chart side came back empty -- IS NULL keeps only the
--  tracks that found NO chart row: the anti-join
--ORDER BY listeners, biggest first -- the most visible rows,
--  where a missed match would be most obvious
--LIMIT only show the top 30
SELECT t.artist,
       t.track,
       t.listeners,
       t.plays_per_listener
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
WHERE s.title IS NULL
ORDER BY t.listeners DESC
LIMIT 30;

-- ============================================================
-- STEP 27: HOW MANY UNMATCHED TITLES CARRY A " - " DASH SUFFIX?
-- WHY: Step 26 caught "Dreams - 2004 Remaster" -- a #1 hit
-- unmatched because streaming services append version tags
-- with a spaced dash. Before writing a trim rung, size it and
-- read it. The spaced dash (space-hyphen-space) is deliberate:
-- it cannot match hyphenated words like "Heart-Shaped Box",
-- which is a real title.
-- RESULT: the eyeball was unambiguous -- every dash tail in the
-- top 20 is a version annotation ("- Remastered 2011",
-- "- Single Version", "- Radio Edit", a soundtrack subtitle)
-- on songs that plainly charted; Bohemian Rhapsody and Hotel
-- California were sitting in the "never charted" pool. DESIGN
-- DECISION: for the match key, cut the title at a spaced dash.
-- Recorded cost: a real title genuinely containing " - " could
-- false-match its stem; annotation tails utterly dominate.
-- ============================================================

--SELECT the count of unmatched tracks containing " - " (display)
--FROM the anti-join (LEFT JOIN + IS NULL)
SELECT COUNT(*) AS unmatched_with_dash
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
WHERE s.title IS NULL
  AND t.track LIKE '% - %';

--SELECT the biggest examples to eyeball (display)
--FROM the same anti-join
--ORDER BY listeners, biggest first
--LIMIT only show 20
SELECT t.artist,
       t.track,
       t.listeners
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
WHERE s.title IS NULL
  AND t.track LIKE '% - %'
ORDER BY t.listeners DESC
LIMIT 20;

-- ============================================================
-- STEP 28: ADD THE DASH-TAIL RUNG, REBUILD KEYS, RE-MEASURE
-- WHY: the title key now needs two LAYERS: first cut any feat/
-- with tail, THEN cut anything from a spaced dash onward. Two
-- layers are hard to read as one giant expression, so the build
-- uses a STAGING TABLE: stage 1 computes the feat/with cut,
-- stage 2 computes the dash cut on stage 1's result, then the
-- staging table is dropped. The verdict is the match rate.
-- PROCESS NOTE from the build: the first run of this step
-- changed the rate by EXACTLY nothing -- because an older block
-- still sitting in the editor got executed instead. When a rule
-- change produces zero difference to the digit, suspect the
-- rule never ran before suspecting it is wrong; clear the
-- editor, run only the new block.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 13,099 / 5,059 / 38.6% -- the dash rung recovered 206
-- more matches (from 4,853). Cleaning STOPS here: rungs
-- recovered 763, then 206, and the one remaining named defect
-- (' vs. ') appeared once -- diminishing returns are the signal.
-- The residual is documented, not chased.
-- ============================================================

--DROP the old tables so the step re-runs cleanly from the top
DROP TABLE IF EXISTS devoted_tracks;
DROP TABLE IF EXISTS stage_tracks;

--CREATE TABLE stage_tracks AS: layer 1 of the title key
--SELECT each devoted track with title_cut1 = the title minus any
--  feat/with tail (the Step 24 CASE ladder, unchanged)
--FROM lastfm_tracks, WHERE both thresholds pass
CREATE TABLE stage_tracks AS
SELECT artist,
       track,
       playcount,
       listeners,
       ROUND(CAST(playcount AS REAL) / listeners, 1) AS plays_per_listener,
       CASE
         WHEN INSTR(LOWER(track), ' (feat.') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (feat.') - 1)
         WHEN INSTR(LOWER(track), ' (with ') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (with ') - 1)
         ELSE track
       END AS title_cut1
FROM lastfm_tracks
WHERE listeners >= 1000
  AND CAST(playcount AS REAL) / listeners >= 6;

--CREATE TABLE devoted_tracks AS: layer 2 finishes the key
--SELECT everything from stage 1, plus:
--  * artist_key  the artist lowercased
--  * title_key   title_cut1 with anything from ' - ' onward cut
--    off (INSTR finds the dash, SUBSTR keeps what's before it),
--    then TRIMmed and lowercased
--FROM the stage_tracks staging table (pull from)
CREATE TABLE devoted_tracks AS
SELECT artist,
       track,
       playcount,
       listeners,
       plays_per_listener,
       LOWER(artist) AS artist_key,
       LOWER(TRIM(CASE
         WHEN INSTR(title_cut1, ' - ') > 0
           THEN SUBSTR(title_cut1, 1, INSTR(title_cut1, ' - ') - 1)
         ELSE title_cut1
       END)) AS title_key
FROM stage_tracks;

--DROP the staging table -- its job is done, the keys are stored
DROP TABLE stage_tracks;

--SELECT the match rate, same three numbers as Step 25 (display)
--FROM devoted_tracks LEFT JOINed to song_keys on both plain keys
SELECT COUNT(*) AS devoted_tracks,
       SUM(s.title IS NOT NULL) AS matched_to_chart,
       ROUND(SUM(s.title IS NOT NULL) * 100.0 / COUNT(*), 1) AS match_rate_pct
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key;

-- ============================================================
-- STEP 29: BUILD THE GEMS TABLE -- THE PAYOFF QUERY
-- WHY: a gem = a devoted track (1,000+ listeners, 6+ plays per
-- listener, cleaned match keys) that finds NO chart row -- the
-- anti-join. GROUP BY the two match keys collapses duplicates
-- (case-twin artists fetched twice, title variants sharing a
-- cleaned key) into one row per real song. Display names use
-- MIN: a clean stem sorts alphabetically before its tailed
-- variants, so MIN(track) shows "Everlong", not "Everlong -
-- acoustic version" (the first build used MAX and learned this
-- the visible way). Stats use MAX: the gem's biggest recorded
-- numbers across its variant rows.
-- THE TIER LADDER: the first read of the results caught famous
-- songs in the "hidden" list -- "never charted" includes
-- world-famous songs (the pre-1999 single rule). Hidden and
-- famous are different constructs, so a FAME CEILING was priced
-- from the gems' own listener distribution (Step 31 bands:
-- under 10k = 777, 10k-50k = 1,356, 50k-200k = 2,524,
-- 200k-1M = 2,862, 1M+ = 309) and DECIDED at 200,000:
--   hidden gem     < 200,000 listeners ("fewer than a fifth of
--                  a million people ever found this")
--   buried anthem  1,000,000+ (famous, never charted -- the
--                  chart's blind spot, the story tier)
--   middle band    everything between (recorded as neither)
-- A CASE ladder stamps the tier -- bucketing, one of CASE's
-- four classic jobs.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 7,828 gems; tier counts matched the Step 31 bands
-- exactly (4,657 hidden / 2,862 middle / 309 anthems).
-- ============================================================

--DROP any earlier build so the step re-runs cleanly
DROP TABLE IF EXISTS gems;

--CREATE TABLE gems AS: the anti-join survivors, tiered
--SELECT for each gem (stored columns)
--  * MIN spellings for display, MAX stats
--  * tier: the CASE ladder on the gem's listeners
--FROM devoted_tracks anti-joined to song_keys (IS NULL keeps
--  only never-charted tracks), GROUP BY the two match keys
CREATE TABLE gems AS
SELECT MIN(t.artist) AS artist,
       MIN(t.track) AS track,
       MAX(t.listeners) AS listeners,
       MAX(t.playcount) AS playcount,
       MAX(t.plays_per_listener) AS plays_per_listener,
       CASE
         WHEN MAX(t.listeners) < 200000 THEN 'hidden gem'
         WHEN MAX(t.listeners) >= 1000000 THEN 'buried anthem'
         ELSE 'middle band'
       END AS tier
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
WHERE s.title IS NULL
GROUP BY t.artist_key, t.title_key;

--SELECT each tier and its count (display)
--FROM the gems table, GROUP BY tier
SELECT tier,
       COUNT(*) AS gem_count
FROM gems
GROUP BY tier
ORDER BY gem_count DESC;

-- ============================================================
-- STEP 30: READ THE GEMS -- TWO RANKINGS
-- WHY: the same gems tell two stories depending on the sort.
-- By listeners, the list leads with REACH: the most widely-
-- found songs that never charted -- necessarily the famous end
-- (a listeners sort puts the best-known rows on top by
-- definition). By plays_per_listener, it leads with DEVOTION.
-- Reading both is also a clerical review of the tiers.
-- RESULT: the reach list = the buried-anthem story (Everlong,
-- The Scientist, Chop Suey!, Don't Speak, six Nirvana cuts --
-- the 90s single-rule era wall to wall). The devotion read
-- surfaced one more noise class, measured in Step 33.
-- ============================================================

--SELECT the devotion ranking (display)
--FROM the gems table (pull from)
--ORDER BY plays_per_listener, biggest first; listeners breaks ties
--LIMIT only show the top 25
SELECT artist,
       track,
       listeners,
       plays_per_listener
FROM gems
ORDER BY plays_per_listener DESC, listeners DESC
LIMIT 25;

--SELECT the reach ranking (display)
--FROM the gems table (pull from)
--ORDER BY listeners, biggest first
--LIMIT only show the top 25
SELECT artist,
       track,
       listeners,
       plays_per_listener
FROM gems
ORDER BY listeners DESC
LIMIT 25;

-- ============================================================
-- STEP 31: WHERE DO THE GEMS' AUDIENCE SIZES SIT?
-- WHY: pricing the fame ceiling for the tier ladder -- the
-- distribution the Step 29 tiers were chosen from. Candidates:
-- ceiling at 50k keeps 2,133 (strictly obscure); 200k keeps
-- 4,657; 1M keeps 7,519 (too loose -- a song 900,000 people
-- know isn't hidden).
-- RESULT: 777 / 1,356 / 2,524 / 2,862 / 309 (sums to 7,828).
-- DECISION: 200,000 -- the same order of fame ceiling that kept
-- a comparable games-market gems analysis honest, wide enough
-- to rank and slice.
-- ============================================================

--SELECT five counts side by side (display)
--  (a comparison returns 1/0, so SUM counts the band)
--FROM the gems table (pull from)
SELECT SUM(listeners < 10000) AS under_10k,
       SUM(listeners >= 10000 AND listeners < 50000) AS band_10k_50k,
       SUM(listeners >= 50000 AND listeners < 200000) AS band_50k_200k,
       SUM(listeners >= 200000 AND listeners < 1000000) AS band_200k_1m,
       SUM(listeners >= 1000000) AS band_1m_plus
FROM gems;

-- ============================================================
-- STEP 32: THE TOP 25 HIDDEN GEMS, BY DEVOTION
-- WHY: the founding question, answerable at last: songs by
-- chart-proven artists that fewer than 200,000 people found,
-- that those finders replay 6+ times each, never on the Hot
-- 100. This read is the tier's clerical review: nothing here
-- should be a song a normal person would call famous.
-- RESULT (first read): genuinely hidden -- 1950s Joni James
-- next to Travis Scott album cuts -- but alternate-VERSION
-- titles crowded the top (instrumentals, sped up / slowed
-- down, remixes; fan-community streaming gives versions
-- extreme ratios). A version of a song is not a distinct
-- buried song. Step 33 measures; Step 34 removes.
-- RESULT (after cleanup): the list spans the 1950s to now --
-- Joni James, Anita Bryant, Jody Miller, Lynn Anderson,
-- Hi-Five, Ke$ha, Travis Scott deep cuts, K-pop b-sides.
-- Remaining notes on the ledger: one '(dance mix)' straggler
-- (bare 'mix' was not a marker), Korean ':: OST' tags, and
-- organized K-pop fandom devotion -- real listening, named in
-- the limitations as a cultural skew of the metric, alongside
-- the platform skew (Last.fm hears streaming-era listeners;
-- a 1965 audience's devotion left no scrobbles).
-- ============================================================

--SELECT the hidden gems' display columns (display)
--FROM the gems table (pull from)
--WHERE only the hidden gem tier
--ORDER BY plays_per_listener, biggest first; listeners breaks ties
--LIMIT only show the top 25
SELECT artist,
       track,
       listeners,
       plays_per_listener
FROM gems
WHERE tier = 'hidden gem'
ORDER BY plays_per_listener DESC, listeners DESC
LIMIT 25;

-- ============================================================
-- STEP 33: HOW MUCH OF THE HIDDEN TIER IS VERSION SPAM?
-- WHY: rule before measurement is banned here, so: count how
-- many hidden-tier titles carry each version marker. LOWER()
-- catches any capitalization.
-- RESULT: remixes 33, instrumentals 9, speed variants 3,
-- 'version' 50, live cuts 13 -- roughly 108 of 4,657 (2%). It
-- LOOKED like a flood because extreme ratios pushed them all to
-- the top of the ranking; as a population it is a delete-and-
-- document situation, not a redesign.
-- ============================================================

--SELECT six counts side by side (display)
--FROM the gems table (pull from)
--WHERE only the hidden gem tier
SELECT SUM(LOWER(track) LIKE '%remix%') AS remixes,
       SUM(LOWER(track) LIKE '%instrumental%' OR LOWER(track) LIKE '%(inst%') AS instrumentals,
       SUM(LOWER(track) LIKE '%sped up%' OR LOWER(track) LIKE '%slowed%') AS speed_variants,
       SUM(LOWER(track) LIKE '%version%' OR LOWER(track) LIKE '% ver.%') AS versions,
       SUM(LOWER(track) LIKE '% live%' OR LOWER(track) LIKE '%(live%') AS live_cuts,
       COUNT(*) AS hidden_tier_total
FROM gems
WHERE tier = 'hidden gem';

-- ============================================================
-- STEP 34: REMOVE VERSION VARIANTS FROM THE GEMS
-- WHY: a version of a song is not a distinct buried song, so
-- version-tagged rows are removed from gems entirely (all
-- tiers). NEW TOOL -- DELETE FROM: permanently removes rows
-- matching a test. Safe HERE because gems is a DERIVED table:
-- the raw Last.fm data is untouched and the whole table
-- rebuilds from Step 29 if ever needed. Never DELETE from raw
-- imported tables. The counts around the delete put the
-- removal on record.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 7,828 before, 7,692 after -- 136 version variants
-- removed across all tiers, in line with the Step 33
-- measurement. The re-read of the Step 32 ranking then read
-- clean (see Step 32's after-cleanup RESULT).
-- ============================================================

--SELECT the row count before the delete (display)
SELECT COUNT(*) AS gems_before
FROM gems;

--DELETE FROM gems: remove rows matching any version marker
DELETE FROM gems
WHERE LOWER(track) LIKE '%remix%'
   OR LOWER(track) LIKE '%instrumental%'
   OR LOWER(track) LIKE '%(inst%'
   OR LOWER(track) LIKE '%sped up%'
   OR LOWER(track) LIKE '%slowed%'
   OR LOWER(track) LIKE '%version%'
   OR LOWER(track) LIKE '% ver.%'
   OR LOWER(track) LIKE '% live%'
   OR LOWER(track) LIKE '%(live%';

--SELECT the row count after the delete (display)
SELECT COUNT(*) AS gems_after
FROM gems;

-- ============================================================
-- STEP 35: FREEZE THE TOP 500 HIDDEN GEMS
-- WHY: the enrichment plan (album + genre tags + duration from
-- a per-track API call via scripts/fetch_lastfm_details.py,
-- decade from the artist's chart era) costs one API request per
-- track, so the list gets FROZEN first: the top 500 hidden-tier
-- gems by devotion, saved as their own table. The fetch script
-- reads this table the same way the first script read
-- known_artists -- the database itself is the handoff.
-- After running: Write Changes (Ctrl+S).
-- RESULT: exactly 500 rows.
-- ============================================================

--DROP any earlier build so the step re-runs cleanly
DROP TABLE IF EXISTS top_gems;

--CREATE TABLE top_gems AS: the enrichment roster
--SELECT every gem column (stored columns)
--FROM the gems table (pull from)
--WHERE only the hidden gem tier
--ORDER BY plays_per_listener, biggest first; listeners breaks ties
--LIMIT keep the top 500
CREATE TABLE top_gems AS
SELECT artist,
       track,
       listeners,
       playcount,
       plays_per_listener
FROM gems
WHERE tier = 'hidden gem'
ORDER BY plays_per_listener DESC, listeners DESC
LIMIT 500;

--SELECT the count -- must be exactly 500 (display)
SELECT COUNT(*) AS top_gem_count
FROM top_gems;

-- ============================================================
-- STEP 36: ENRICH THE TOP 500 (Python, outside this file)
-- WHY: the top-500 list is stronger as a browsable page with
-- album, genre, and duration columns. SQL cannot call the
-- internet, so scripts/fetch_lastfm_details.py collects them:
-- it reads the 500 frozen gems straight from top_gems, calls
-- the track.getInfo endpoint once per gem, and keeps the album,
-- the top 3 community TAGS (pipe-joined), and the duration.
-- TAG FALLBACK: track-level tags exist for only ~3% of hidden
-- gems (obscure tracks accumulate none). When a track has no
-- tags, the ARTIST's top tags are used instead (one
-- artist.gettoptags call per DISTINCT artist, cached so repeat
-- artists cost nothing). "Genre of the artist" is the honest
-- reading -- stated on the page.
-- RESULT: 500 enriched, 0 failed -> data/gem_details_2026-07-15
-- .csv. Coverage: album 469/500, tags 500/500 (14 track-level +
-- the rest via the artist fallback), duration 447/500. Gaps
-- are documented, not errors. Imported as table gem_details
-- (columns artist, track, album, tags, duration_ms) with every
-- dialog field set explicitly, then Write Changes.
-- ============================================================

-- ============================================================
-- STEP 37: ASSEMBLE gem_page -- THE WEB-READY DATASET
-- WHY: the page needs sortable columns pulled from three
-- sources: top_gems (the frozen 500 with devotion stats),
-- gem_details (album, tags, duration), and chart_entries (the
-- DECADE source). Gems have no release dates (the API returns
-- none, and a never-charted song has no chart date), so decade
-- is the ARTIST'S DEBUT DECADE: the decade of their first Hot
-- 100 week -- honest, and labeled that way on the page.
-- HOW THE PIECES READ:
--   * the era subquery maps every performer credit back to its
--     primary artist (the distinct pairs artist_songs stores),
--     then takes MIN chart_week per artist as the debut
--   * decade: SUBSTR(first_chart, 1, 3) keeps '195' from
--     '1958-08-04'; gluing '0s' on makes '1950s'
--   * genre: the FIRST tag -- SUBSTR up to the first '|' (the
--     INSTR runs on tags with a '|' glued to the end, so
--     single-tag values still find a cut point)
--   * duration: ms -> 'm:ss' via printf('%02d') for zero-padded
--     seconds; unknown (0) becomes empty text
-- LEFT JOINs throughout: a gem missing details or era stays on
-- the page with blanks, never silently dropped. The trailing
-- GROUP BY guards against case-twin artists producing double
-- era rows -- exactly one row per gem.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 500 rows. Decade spread 50s 8 / 60s 12 / 70s 13 /
-- 80s 28 / 90s 41 / 00s 63 / 10s 169 / 20s 166 -- every era
-- represented, modern-heavy (Last.fm audiences skew recent).
-- ============================================================

--DROP any earlier build so the step re-runs cleanly
DROP TABLE IF EXISTS gem_page;

--CREATE TABLE gem_page AS: one web-ready row per top gem
--SELECT (stored columns)
--  * artist, track, listeners, playcount, plays_per_listener
--    from top_gems, carried as-is
--  * album  from gem_details
--  * genre  the first tag in the pipe-joined tags
--  * tags   the full pipe-joined top 3, kept for filtering
--  * duration  'm:ss' text from duration_ms, '' when unknown
--  * debut_decade  the artist's first-chart-week decade
--FROM the top_gems table AS g (pull from)
--LEFT JOIN gem_details AS d on exact artist and track
--LEFT JOIN the era subquery AS e on lowercased artist name
CREATE TABLE gem_page AS
SELECT g.artist,
       g.track,
       g.listeners,
       g.playcount,
       g.plays_per_listener,
       d.album,
       CASE
         WHEN d.tags IS NULL OR d.tags = '' THEN ''
         ELSE SUBSTR(d.tags, 1, INSTR(d.tags || '|', '|') - 1)
       END AS genre,
       d.tags,
       CASE
         WHEN d.duration_ms IS NULL OR d.duration_ms = 0 THEN ''
         ELSE (d.duration_ms / 60000) || ':' ||
              printf('%02d', (d.duration_ms / 1000) % 60)
       END AS duration,
       SUBSTR(e.first_chart, 1, 3) || '0s' AS debut_decade
FROM top_gems AS g
LEFT JOIN gem_details AS d
  ON g.artist = d.artist
 AND g.track = d.track
LEFT JOIN (SELECT m.primary_artist,
                  MIN(c.chart_week) AS first_chart,
                  MAX(c.chart_week) AS last_chart
           FROM chart_entries AS c
           JOIN (SELECT DISTINCT performer, primary_artist
                 FROM artist_songs) AS m
             ON c.performer = m.performer
           GROUP BY m.primary_artist) AS e
  ON LOWER(e.primary_artist) = LOWER(g.artist)
GROUP BY g.artist, g.track;

--SELECT the count -- expect 500 (display)
SELECT COUNT(*) AS page_rows
FROM gem_page;

-- ============================================================
-- STEP 38: ADD THE GEM SCORE (0-100), WEIGHTED 70/30
-- WHY: the page wants one default sort balancing the two things
-- a great gem has: DEVOTION (plays per listener) and EVIDENCE
-- (enough listeners that the devotion isn't a fluke). The score
-- is a COMPOSITE INDICATOR, built in the open:
--   gem_score = (0.7 x plays-per-listener percentile
--              + 0.3 x listeners percentile) x 100
-- An equal 50/50 first attempt read all-2020s: on Last.fm a big
-- audience means a RECENT audience (streaming-era scrobblers),
-- so any audience weight pulls the list modern, and percentile
-- rank also flattens the true devotion outliers (106.9 and 48.3
-- plays/listener are both just "near rank 500"). DECISION: 70%
-- devotion / 30% audience -- devotion leads, audience only
-- breaks ties. The weights are STATED here and on the page;
-- that transparency is what separates a defensible index from a
-- black box. The modern skew is a data property, not a bug --
-- the page handles era coverage with a DECADE FILTER, not by
-- reweighting (every decade's own top-5 reads familiar).
-- NEW TOOL -- WINDOW FUNCTIONS: PERCENT_RANK() OVER (ORDER BY x)
-- gives each row the fraction of rows below it on x, without
-- collapsing rows the way GROUP BY does. Two windows, one per
-- ingredient. The rebuild uses the staging-copy pattern.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 500 rows scored. Top by score leans 2010s-2020s (V,
-- Stray Kids, Sleep Token, j-hope) as expected; sorted or
-- filtered by decade each era shows its own gems (1950s Joni
-- James, 1970s Lynn Anderson, 1980s Kylie Minogue...). Final
-- dataset exported to data/gems.json for the front-end page.
-- ============================================================

--CREATE TABLE stage_page AS: a working copy of gem_page
DROP TABLE IF EXISTS stage_page;
CREATE TABLE stage_page AS
SELECT * FROM gem_page;

--DROP and rebuild gem_page with the score column
DROP TABLE gem_page;

--CREATE TABLE gem_page AS: every column plus the 70/30 score
--SELECT (stored columns)
--  * every existing column, carried as-is
--  * gem_score: 0.7 times the devotion percentile plus 0.3
--    times the listeners percentile, times 100, ROUNDed to 1
--FROM the stage_page staging copy (pull from)
CREATE TABLE gem_page AS
SELECT artist,
       track,
       listeners,
       playcount,
       plays_per_listener,
       album,
       genre,
       tags,
       duration,
       debut_decade,
       ROUND((0.7 * PERCENT_RANK() OVER (ORDER BY plays_per_listener)
            + 0.3 * PERCENT_RANK() OVER (ORDER BY listeners)) * 100, 1) AS gem_score
FROM stage_page;

--DROP the staging copy -- its job is done
DROP TABLE stage_page;

--SELECT the final default ranking (display)
--ORDER BY gem_score, biggest first
--LIMIT only show the top 15
SELECT artist, track, genre, debut_decade,
       listeners, plays_per_listener, gem_score
FROM gem_page
ORDER BY gem_score DESC
LIMIT 15;

-- ============================================================
-- STEP 39: REBUILD top_gems -- TOP-40 ARTISTS, ONE GEM EACH
-- WHY: reading the first top-500 felt like an obscure-artists
-- list, and a few artists flooded it with multiple songs. Two
-- definition upgrades: (1) the artist must have had a TOP 40
-- hit -- known_artists.career_peak <= 40 (career_peak = the
-- best chart position any of their songs reached), so every
-- name on the page is someone radio genuinely made familiar;
-- (2) ONE gem per artist -- each artist's single most devoted
-- hidden gem -- so the list reads as variety, not domination.
-- The page's promise becomes: "every artist here had a Top 40
-- hit; these songs weren't."
-- NEW TOOL -- ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...):
-- numbers rows 1, 2, 3... WITHIN each group (each artist),
-- restarting at 1 per group, ordered as told. Keeping only the
-- rows numbered 1 = "the best row per group" -- the standard
-- move for exactly this job. PARTITION BY is GROUP BY's cousin
-- that numbers rows instead of collapsing them.
-- ORDER OF OPERATIONS: after this step, re-run the Step 36
-- enrichment script (top_gems changed, so album/genre/duration
-- must be re-fetched for the new roster), re-import
-- gem_details (DROP the old table first -- a same-name CSV
-- import APPENDS instead of replacing), then re-run Steps 37
-- and 38 to rebuild gem_page and its scores.
-- PROCESS NOTE: the first run of this step returned 500 rows /
-- 113 distinct artists -- the OLD roster's fingerprint; a stale
-- editor block had executed (second occurrence -- see Step 28).
-- The verification pair below exists exactly to catch that:
-- the two counts must be EQUAL, or one-per-artist did not hold.
-- After running: Write Changes (Ctrl+S).
-- RESULT: 500 / 500 -- five hundred distinct artists, every one
-- with a Top 40 pedigree, one gem each.
-- ============================================================

--DROP the earlier roster so this replaces it cleanly
DROP TABLE IF EXISTS top_gems;

--CREATE TABLE top_gems AS: the upgraded enrichment roster
--SELECT the gem columns (stored columns)
--FROM a subquery that ranks each artist's hidden gems:
--  (inner: every hidden-tier gem joined to known_artists on
--   lowercased name; keep only artists whose career_peak is 40
--   or better; ROW_NUMBER partitioned by artist, ordered by
--   devotion then listeners, AS gem_rank)
--WHERE only each artist's #1 gem survives (gem_rank = 1)
--ORDER BY devotion, biggest first; listeners breaks ties
--LIMIT keep the top 500
CREATE TABLE top_gems AS
SELECT artist,
       track,
       listeners,
       playcount,
       plays_per_listener
FROM (SELECT g.artist,
             g.track,
             g.listeners,
             g.playcount,
             g.plays_per_listener,
             ROW_NUMBER() OVER (
               PARTITION BY LOWER(g.artist)
               ORDER BY g.plays_per_listener DESC, g.listeners DESC
             ) AS gem_rank
      FROM gems AS g
      JOIN known_artists AS k
        ON LOWER(k.primary_artist) = LOWER(g.artist)
      WHERE g.tier = 'hidden gem'
        AND k.career_peak <= 40)
WHERE gem_rank = 1
ORDER BY plays_per_listener DESC, listeners DESC
LIMIT 500;

--SELECT two verification counts side by side (display)
--  * COUNT(*)  the roster size
--  * COUNT(DISTINCT LOWER(artist))  must EQUAL the row count --
--    the proof that one-per-artist held
SELECT COUNT(*) AS roster_rows,
       COUNT(DISTINCT LOWER(artist)) AS distinct_artists
FROM top_gems;

-- ============================================================
-- STEP 40: PUNCTUATION-PROOF MATCH KEYS (the Eye of the Tiger fix)
-- WHY: a reader caught "Eye Of A Tiger" on the gem list -- a
-- misspelled scrobble variant of a #1 hit, passing as a hidden
-- gem because the typo never charted. The detector built to
-- measure it found the bigger class: 98 false gems existed
-- because Billboard and Last.fm PUNCTUATE differently ("Hey,
-- Soul Sister" vs "Hey Soul Sister"; "Paint It, Black"; "Truly,
-- Madly, Deeply"), plus 4 more from a/an/the swaps ("Boys of
-- Summer" vs "The Boys of Summer"). Ten of those false gems
-- were sitting on the public page draft. The false-merge check
-- came back CLEAN: every same-artist collision the rule creates
-- is the same real song under punctuation variants (both "Let
-- It Snow!" spellings), so the rule is safe. DECISION: match
-- keys are lowercased, feat/with- and dash-cut (Steps 24/28),
-- then stripped of punctuation and the words a/an/the.
-- SQLite has no regex, so the stripping is a chain of nested
-- REPLACE calls -- ugly, honest, and visible: quote characters
-- are deleted outright (so "don't" stays "dont"), other
-- punctuation becomes spaces, the title is padded with spaces
-- so ' a ', ' an ', ' the ' match as whole words, doubles are
-- collapsed, TRIM finishes. Entity resolution's FIFTH
-- appearance in this project: artist credits, letter case,
-- version tags, typos, punctuation.
-- RESULT: match rate 39.4% (5,164 of 13,101), up from 38.6% --
-- 105 recovered matches, "Paint It Black" and "Hey Soul Sister"
-- correctly expelled from gemhood.
-- ============================================================

--Rebuild song_keys with normalized title keys
DROP TABLE IF EXISTS song_keys;
CREATE TABLE song_keys AS
SELECT primary_artist,
       title,
       best_peak,
       total_weeks,
       LOWER(primary_artist) AS artist_key,
       TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
         ' ' || REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           LOWER(title),
           '''',''), '’',''), '‘',''), '"',''), '“',''), '”',''),
           ',',' '), '.',' '), '!',' '), '?',' '), '(',' '), ')',' '),
           '*',' '), ':',' '), ';',' '), '/',' ')
         || ' ',
         ' a ',' '), ' an ',' '), ' the ',' '),
         '  ',' ')) AS title_key
FROM artist_songs;

CREATE INDEX IF NOT EXISTS idx_song_keys ON song_keys (artist_key, title_key);

--Rebuild devoted_tracks: feat/with cut, dash cut, then normalize
DROP TABLE IF EXISTS devoted_tracks;
DROP TABLE IF EXISTS stage_tracks;
CREATE TABLE stage_tracks AS
SELECT artist, track, playcount, listeners,
       ROUND(CAST(playcount AS REAL) / listeners, 1) AS plays_per_listener,
       CASE
         WHEN INSTR(LOWER(track), ' (feat.') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (feat.') - 1)
         WHEN INSTR(LOWER(track), ' (with ') > 0
           THEN SUBSTR(track, 1, INSTR(LOWER(track), ' (with ') - 1)
         ELSE track
       END AS title_cut1
FROM lastfm_tracks
WHERE listeners >= 1000
  AND CAST(playcount AS REAL) / listeners >= 6;

CREATE TABLE devoted_tracks AS
SELECT artist, track, playcount, listeners, plays_per_listener,
       LOWER(artist) AS artist_key,
       TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
         ' ' || REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           LOWER(CASE
             WHEN INSTR(title_cut1, ' - ') > 0
               THEN SUBSTR(title_cut1, 1, INSTR(title_cut1, ' - ') - 1)
             ELSE title_cut1
           END),
           '''',''), '’',''), '‘',''), '"',''), '“',''), '”',''),
           ',',' '), '.',' '), '!',' '), '?',' '), '(',' '), ')',' '),
           '*',' '), ':',' '), ';',' '), '/',' ')
         || ' ',
         ' a ',' '), ' an ',' '), ' the ',' '),
         '  ',' ')) AS title_key
FROM stage_tracks;

DROP TABLE stage_tracks;

--The match rate, the rule's verdict (baseline to beat: 38.6%)
SELECT COUNT(*) AS devoted_tracks,
       SUM(s.title IS NOT NULL) AS matched_to_chart,
       ROUND(SUM(s.title IS NOT NULL) * 100.0 / COUNT(*), 1) AS match_rate_pct
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key;

-- ============================================================
-- STEP 41: REBUILD THE CHAIN ON THE NEW KEYS (3 GEMS PER ARTIST)
-- WHY: Step 40's normalized keys changed who counts as "never
-- charted," so everything downstream rebuilds: gems (anti-join
-- + tiers, the Step 29 pattern), the version-variant removal
-- (the Step 34 rule), and the roster. One definition change
-- rides along, per the product read: UP TO THREE gems per
-- artist instead of one (gem_rank <= 3) -- variety stays, but
-- repeat offenders become visible. Roster rule otherwise
-- unchanged: Top 40 artists only. After this: re-fetch details
-- (Step 36 script), DROP + re-import gem_details, re-run Steps
-- 37-38, re-export gems.json.
-- RESULT: roster 500 rows across 262 distinct artists -- the
-- 3-cap visible (about two gems per artist on average).
-- ============================================================

--Rebuild gems from the new keys (Step 29 pattern, unchanged)
DROP TABLE IF EXISTS gems;
CREATE TABLE gems AS
SELECT MIN(t.artist) AS artist,
       MIN(t.track) AS track,
       MAX(t.listeners) AS listeners,
       MAX(t.playcount) AS playcount,
       MAX(t.plays_per_listener) AS plays_per_listener,
       CASE
         WHEN MAX(t.listeners) < 200000 THEN 'hidden gem'
         WHEN MAX(t.listeners) >= 1000000 THEN 'buried anthem'
         ELSE 'middle band'
       END AS tier
FROM devoted_tracks AS t
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
WHERE s.title IS NULL
GROUP BY t.artist_key, t.title_key;

--Remove version variants (Step 34 rule, unchanged)
DELETE FROM gems
WHERE LOWER(track) LIKE '%remix%'
   OR LOWER(track) LIKE '%instrumental%'
   OR LOWER(track) LIKE '%(inst%'
   OR LOWER(track) LIKE '%sped up%'
   OR LOWER(track) LIKE '%slowed%'
   OR LOWER(track) LIKE '%version%'
   OR LOWER(track) LIKE '% ver.%'
   OR LOWER(track) LIKE '% live%'
   OR LOWER(track) LIKE '%(live%';

--Rebuild the roster: Top 40 artists, up to 3 gems each
DROP TABLE IF EXISTS top_gems;
CREATE TABLE top_gems AS
SELECT artist,
       track,
       listeners,
       playcount,
       plays_per_listener
FROM (SELECT g.artist,
             g.track,
             g.listeners,
             g.playcount,
             g.plays_per_listener,
             ROW_NUMBER() OVER (
               PARTITION BY LOWER(g.artist)
               ORDER BY g.plays_per_listener DESC, g.listeners DESC
             ) AS gem_rank
      FROM gems AS g
      JOIN known_artists AS k
        ON LOWER(k.primary_artist) = LOWER(g.artist)
      WHERE g.tier = 'hidden gem'
        AND k.career_peak <= 40)
WHERE gem_rank <= 3
ORDER BY plays_per_listener DESC, listeners DESC
LIMIT 500;

--Verification: tier counts, then the roster pair
SELECT tier, COUNT(*) AS gem_count
FROM gems
GROUP BY tier
ORDER BY gem_count DESC;

SELECT COUNT(*) AS roster_rows,
       COUNT(DISTINCT LOWER(artist)) AS distinct_artists
FROM top_gems;
