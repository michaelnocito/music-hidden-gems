# Music Hidden Gems 💎🎵

**The music people love that never made mainstream airplay.**

Every artist in this analysis had a Top 40 hit on the Billboard Hot 100. The
songs surfaced here never charted at all — yet the listeners who found them
replay them 6, 10, sometimes 40+ times each. This project joins 68 years of
Billboard chart history to Last.fm listening data with SQL to find them,
systematically.

**Browse and vote on the results:**
👉 **https://michaelnocito.github.io/music-hidden-gems-list/** — the top 500,
sortable by Gem Score, devotion, listeners, or artist; filterable by decade
and genre; downloadable as Excel or a playlist CSV.

---

## The headline findings

**7,574 hidden gems** survived every filter, out of 78,335 tracks analyzed
across 1,570 charting artists. The top 10 by Gem Score:

| # | Song | Artist | Genre | Listeners | Plays/Listener |
|---|------|--------|-------|----------:|---------------:|
| 1 | The Apparition | Sleep Token | alternative metal | 191,554 | 23.3 |
| 2 | Ascensionism | Sleep Token | progressive metal | 171,081 | 23.2 |
| 3 | Bad Omens | 5 Seconds Of Summer | pop punk | 191,958 | 18.9 |
| 4 | think later | Tate McRae | pop | 198,788 | 17.0 |
| 5 | No Shame | 5 Seconds Of Summer | pop punk | 195,791 | 16.6 |
| 6 | Euclid | Sleep Token | progressive metal | 141,869 | 22.9 |
| 7 | Full machine | Gracie Abrams | pop | 166,858 | 18.1 |
| 8 | No Complaints | Noah Kahan | indie | 189,012 | 16.4 |
| 9 | This Is What The Drugs Are For | Gracie Abrams | pop | 167,232 | 17.5 |
| 10 | Vulnerable | Selena Gomez | pop | 180,591 | 16.5 |

### The buried anthems (a chart-history story)

The analysis also surfaced 292 **famous** songs that never charted — a
separate tier, because a song 3 million people know isn't "hidden":

| Song | Artist | Listeners |
|------|--------|----------:|
| Everlong | Foo Fighters | 3,191,120 |
| The Scientist | Coldplay | 3,089,149 |
| About a Girl | Nirvana | 2,638,657 |
| Basket Case | Green Day | 2,615,626 |
| Boys Don't Cry | The Cure | 2,446,239 |

There's a reason the 90s dominate this tier: until December 1998, Billboard
required a commercially released physical single for a song to chart, and
90s alternative bands famously didn't release them. "Don't Speak" — the
biggest airplay song of its year — never appeared on the Hot 100. The
chart's own rules created a blind spot, and the data shows it plainly.

### Who has the Hot 100 seen most?

| Artist | Songs charted | Career peak |
|--------|--------------:|:-----------:|
| Taylor Swift | 270 | #1 |
| Drake | 261 | #1 |
| Glee Cast | 206 | #4 |
| Elvis Presley | 107 | #1 |
| Morgan Wallen | 97 | #1 |

(Elvis only reaches 107 after entity resolution — his catalog was split
across **seven** different credit strings in the raw data. See below.)

## How a gem is defined

Every threshold was chosen from a measured distribution, never guessed —
the alternatives and their costs are recorded in the SQL file:

| Rule | Value | Where it came from |
|------|-------|--------------------|
| "Known artist" | 5+ charted songs | 57% of charting artists chart exactly once; candidates 3/5/10 kept 2,596/1,570/740 artists |
| Top 40 pedigree (top-500 list) | career peak ≤ 40 | every artist on the public list is someone radio made famous |
| Listener floor | ≥ 1,000 | ratios lie on tiny denominators; 17% of tracks sat below 1k |
| Fame ceiling ("hidden") | < 200,000 listeners | from the gems' own audience distribution |
| Devotion | ≥ 6 plays per listener | the typical track sits at 2–4; 6+ keeps the top 20% |
| Gem Score | 70% devotion percentile + 30% audience percentile | weights stated, on purpose: a small obsessed audience beats a big casual one |

## What it took (the honest part)

The interesting work was never the final query — it was the data refusing to
cooperate, documented issue by issue in [docs/DATA_QUALITY.md](docs/DATA_QUALITY.md):

- **One artist, seven names.** "Elvis Presley With The Jordanaires" is a
  different string than "Elvis Presley." Up to 43% of credit strings carry a
  joiner word; a CASE-ladder normalization rule was built by
  preview-catch-fix iteration.
- **When NOT to merge.** Splitting on "&" would have shredded Hall & Oates
  and Earth, Wind & Fire into artists that don't exist. Measured, refused,
  documented.
- **Punctuation almost ruined everything.** Billboard prints "Paint It,
  Black"; Last.fm says "Paint It Black". Before punctuation-proof match
  keys, 98 famous charted songs were masquerading as hidden gems (a reader
  caught "Eye Of A Tiger" — a scrobble typo — on the draft list).
- **Version spam.** Remixes, instrumentals, sped-up and slowed-down cuts:
  measured at 2% of the pool, deleted with the removal on record.
- **The tools fought back too.** A function-wrapped join ran 30+ minutes
  (fix: precomputed, indexed match keys); a database GUI's unsaved-changes
  model made tables visible to the eye and invisible to scripts.

## Learn from this project

The SQL is written as a teaching file: every step has a boxed WHY, a
read-out-loud narration of each clause, and its confirmed RESULT.

- [queries/hidden_gems.sql](queries/hidden_gems.sql) — the full analysis,
  Steps 3–41, from raw import to the scored top 500
- [docs/](docs/) — companion guides: setup, joins from zero, CASE
  expressions, data-driven thresholds, API keys, how to study this file
- [docs/EXTEND_THIS_PROJECT.md](docs/EXTEND_THIS_PROJECT.md) — ways to push
  the analysis further using only the skills taught here
- Python side: [scripts/fetch_lastfm.py](scripts/fetch_lastfm.py) and
  [scripts/fetch_lastfm_details.py](scripts/fetch_lastfm_details.py) — the
  API collection scripts (SQL can't call the internet; these are the bridge)

## Reproduce it

1. Chart data: the Billboard Hot 100 weekly archive CSV from
   [utdata/rwd-billboard-data](https://github.com/utdata/rwd-billboard-data)
   (included here as `data/hot-100-current.csv`).
2. Database setup: [docs/SETUP.md](docs/SETUP.md) (SQLite + DB Browser,
   free, no server).
3. Last.fm side: get a free API key
   ([docs/GET_AN_API_KEY.md](docs/GET_AN_API_KEY.md)), run the fetch
   scripts. Or use the committed snapshots in `data/` (July 2026).
4. Work through `queries/hidden_gems.sql` step by step.

## Limitations (stated, not hidden)

- Last.fm hears streaming-era listeners: older devotion is under-counted,
  so the unfiltered ranking skews modern. Decade and genre are filters on
  the list site for exactly this reason.
- Genre = the top community tag; usually right, occasionally a fan joke.
- "&"-joined duos stay unsplit (by design); a duo member's solo career
  never merges with their duo work.
- Pre-1999 "never charted" partly reflects Billboard's commercial-single
  rule rather than radio's verdict.
- Numbers are a dated snapshot (July 2026); Last.fm counts move daily.

## Data sources

- [Billboard Hot 100 archive](https://github.com/utdata/rwd-billboard-data)
  (UT-Austin journalism), 1958-08-04 → 2026-07-11: 354,500 chart entries
- [Last.fm API](https://www.last.fm/api): 78,335 tracks (top tracks per
  charting artist), plus per-track album/tags/duration for the top 500

## About

Part of a hidden-gems series:
[Steam Hidden Gems](https://github.com/michaelnocito/steam-hidden-gems) ·
[Streaming Hidden Gems](https://github.com/michaelnocito/streaming-hidden-gems) ·
Music Hidden Gems (this repo).

Built by [Michael Nocito](https://michaelnocito.github.io), data analyst.
Free analyst learning kits: [Analyst Prep Kit](https://michaelnocito.github.io/analyst-prep-kit/).
