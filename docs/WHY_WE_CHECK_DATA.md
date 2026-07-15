# Why Analysts Interrogate Data Before Analyzing It

You have a dataset and a question you can't wait to ask it. This page is about
the discipline of NOT asking it yet, what the industry calls the work, why it
exists, and how to recognize when something needs digging.

## The industry terms

- **Data profiling.** The systematic first look at a dataset: row counts, column
  types, value ranges, distinct values, missing-value counts. Profiling is not
  optional pre-work; it is how you learn what the data actually is, as opposed
  to what its documentation claims.
- **Data validation / sanity checks.** Comparing what the data says against
  what it MUST say if it is healthy: an expected row count, totals that should
  reconcile, values that must fall in a known range (a chart position must be
  1-100).
- **Exploratory data analysis (EDA).** The broader habit, named by statistician
  John Tukey in the 1970s: look at the data from several angles before modeling
  or reporting, and let what you see reshape your assumptions.
- **Garbage in, garbage out (GIGO).** The reason all of this exists. No query,
  however elegant, survives being run against data that was silently broken on
  arrival.

## The six data quality dimensions

The industry-standard framework ([DAMA-DMBOK](https://www.dataversity.net/articles/data-quality-dimensions/),
the data management body of knowledge) evaluates data on
[six core dimensions](https://www.cleverrepublic.com/resources/blog/the-six-most-used-data-quality-dimensions/).
Each one is a question you can ask of any table, and each maps to a concrete
check this project actually ran:

| Dimension | The question | How this project checked it |
|---|---|---|
| **Completeness** | Is anything missing? | Expected ~350k rows from first principles (100 songs x weekly charts since 1958); got 354,500. Counted blanks: zero. |
| **Validity** | Do values follow their rules? | Chart positions should be numeric; two columns arrived as TEXT. Hunted down why (found the text marker 'NA'). |
| **Consistency** | Does the data agree with itself? | Distinct weeks x 100 exactly equals total rows. But "no previous week" is marked TWO ways ('NA' and '0'), an inconsistency now documented. |
| **Uniqueness** | Are there duplicates? | Each chart week appears exactly once per song position (the x100 arithmetic would break otherwise). |
| **Accuracy** | Does it match reality? | Spot-checked rows against known facts (the first Hot 100 was published 1958-08-04; row 1 of the earliest week matches history). |
| **Timeliness** | Is it current enough? | Latest chart week within days of the download date; coverage window recorded so later claims stay inside it. |

## How to recognize that something needs digging

Profiling produces facts; these are the facts that should raise your eyebrows.
Every one of them is a cheap observation that, ignored, becomes an expensive
wrong answer:

1. **More (or fewer) columns than the header names.** Rows are splitting or
   merging during import. Something structural is wrong with separators or
   quoting.
2. **A numeric-looking column typed as TEXT.** The import tool saw at least one
   value it could not treat as a number, OR it is being cautious. Either way,
   you don't know until you look, and text math fails silently ('9' sorts
   after '100').
3. **A row count that ignores your expectation.** Always compute what the count
   SHOULD be from first principles before running COUNT(*). No expectation =
   no way to notice dropped rows, and import tools can drop thousands without
   an error message.
4. **Suspicious round numbers, or numbers that fail arithmetic cross-checks.**
   Two independent queries that should agree (total rows vs distinct weeks x
   100) and don't = something is duplicated or missing.
5. **Multiple spellings of the same idea.** 'NA' and '0' both meaning "none";
   'true' vs 'TRUE' vs 1; the same artist credited three different ways.
   Usually a sign the dataset was stitched from multiple sources or eras.
6. **Values outside their legal range.** Positions above 100, negative counts,
   dates in the future. Define the legal range first, then test it.
7. **A file dramatically smaller or larger than advertised.** A few-KB download
   that should be many MB is an error page, not data.

## The digging method (hypothesis-driven)

When a signal fires, don't scroll aimlessly. Dig the way a debugger works:

1. **State a hypothesis.** "The TEXT type is caused by blank cells."
2. **Write the cheapest query that can kill it.** Count the blanks.
3. **Reject and narrow.** Zero blanks? Next hypothesis: any non-digit value
   anywhere. Pattern-match for it.
4. **Quantify what you find.** Finding the oddity is not the end; its COUNT
   decides the handling. A handful of rows gets documented and stepped around;
   tens of thousands mean the oddity is part of the data's language and every
   later query must speak it.
5. **Write it down.** Every confirmed finding goes in the project's data notes
   with the query that proved it. Future readers (including future you) inherit
   the conclusions instead of re-running the hunt.

Sometimes the answer is "nothing is wrong" (this project's peak_pos column
passed every test and had merely been typed cautiously by the import tool).
That is not wasted work. A verified-clean column is a different thing from an
assumed-clean column, and only one of them belongs under an analysis.

## The payoff

The checks above cost a handful of one-line queries, minutes of work. What they
buy: every later query in this project inherits verified facts (exact row
counts, known missing-value markers, safe casting rules) instead of assumptions.
In professional settings this is the difference between an analysis that
survives review and one that gets retracted after someone notices the numbers
were quietly wrong from the start.

Further reading: [DAMA data quality dimensions](https://www.dataversity.net/articles/data-quality-dimensions/),
[the six most used dimensions](https://www.cleverrepublic.com/resources/blog/the-six-most-used-data-quality-dimensions/),
[8 dimensions of data quality](https://www.cloverdx.com/blog/8-dimensions-data-quality).
