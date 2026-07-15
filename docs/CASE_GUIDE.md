# The CASE Expression, Explained From Zero

The construct that keeps appearing in this project's queries:

```sql
CASE
  WHEN <test 1> THEN <value 1>
  WHEN <test 2> THEN <value 2>
  ELSE <fallback value>
END
```

## What it is

CASE is SQL's if/else. It checks each WHEN test **top to bottom**, and the
**first test that passes wins**: its THEN value is the result and everything
below is skipped. If no test passes, the ELSE value is the result (and if
there is no ELSE, the result is NULL).

The multi-branch form above has an official name: a **searched CASE
expression**. Analysts informally call the shape a **CASE ladder**: a stack of
WHEN/THEN rungs. If you know other programming languages, it is the same idea
as an if / else-if / else chain or a switch statement.

There is also a compact second form, the **simple CASE**, which compares one
value against a list of candidates:

```sql
CASE grade
  WHEN 'A' THEN 4.0
  WHEN 'B' THEN 3.0
  ELSE 0.0
END
```

The searched form is the more general and more common of the two, because
each rung can hold any test, not just equality against one value.

## The two rules that matter

**1. Order is logic.** Because the first match wins, rung order changes the
answer. This project learned it on real data: the credit
"2Pac Duet With Mopreme" must be cut before ' Duet With ', but a rung testing
the more general ' With ' placed above it would match first and cut in the
wrong place, producing the fake artist "2Pac Duet". The rule that follows:
**specific patterns above the general patterns they contain.** The project's
finished ladder reads ' A Duet With ', then ' Duet With ', then ' Featuring ',
then ' With ', each rung more general than the one above it.

**2. It is an expression, not a command.** CASE produces a value per row, the
way a column does. That means it can sit anywhere a column can:

- in a SELECT (compute a new column),
- in a WHERE (filter on the computed value),
- in an ORDER BY (custom sort orders),
- inside CREATE TABLE ... AS (bake the computed value into a saved table),
- inside an aggregate like SUM or COUNT (see below).

## What the industry uses CASE for

- **Cleaning and normalizing.** Mapping messy source values onto clean ones.
  This project's primary-artist rule is exactly this: five rungs that turn
  9,000+ messy credit strings into clean artist names.
- **Bucketing.** Turning a continuous number into named bands:
  `CASE WHEN age < 18 THEN 'minor' WHEN age < 65 THEN 'adult' ELSE 'senior' END`.
  Revenue tiers, engagement bands, and rating groups all work this way.
- **Flags.** A yes/no column computed from a test:
  `CASE WHEN best_peak <= 10 THEN 1 ELSE 0 END AS top10_hit`.
- **Conditional aggregation** (the pivot trick): putting CASE inside SUM or
  COUNT counts different things in one pass over the table:
  `SUM(CASE WHEN genre = 'Country' THEN 1 ELSE 0 END) AS country_songs`.
  One query, many tailored counts side by side. (SQLite lets a bare
  comparison act as 1/0, so `SUM(genre = 'Country')` is the local shorthand;
  the CASE version is the portable industry spelling.)

## How to build a ladder that is actually correct

The method this project used, which generalizes to any normalization work:

1. Write the rule you believe in, as a ladder.
2. **Preview it on real rows** before building anything from it: original
   value and computed value side by side, and read them.
3. When a wrong output appears, identify the missing rung, place it above the
   general rung that mis-handled it, and re-preview.
4. Confirm each fix on the exact rows it targets, not just a random sample.
5. Iterate until the exceptions stop appearing. That is genuinely how
   normalization rules get built in practice.

Related pages: [JOINS_GUIDE.md](JOINS_GUIDE.md) for the join concepts this
ladder feeds into, [DATA_QUALITY.md](DATA_QUALITY.md) for the full story of
the data that made the ladder necessary.
