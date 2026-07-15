# Extend This Project (No New Skills Required)

Reading a finished analysis teaches you a little. Changing one and watching
the results move teaches you a lot more — learning science calls it the
generation effect: producing an answer beats reading one. Every idea below
uses only tools already used in `queries/hidden_gems.sql` (`WHERE`, `LIKE`,
`CAST`, `GROUP BY`, `HAVING`, `ORDER BY`, CASE, subqueries, and joins). If
you followed the walkthrough, you can do all of it.

The method for each idea: predict what will happen first, run it, compare.
The gap between your prediction and the result is where the learning is.

## Change the definition of "known"

1. **Move the roster cutoff.** The roster keeps artists with 5+ charted
   songs. Rebuild it at 3+ and at 10+ (the walkthrough already measured
   how many artists each keeps). How does the gem list change when
   "known" gets stricter?
2. **Chart-toppers only.** Filter the roster to `career_peak = 1` —
   artists who have topped the chart at least once. Gems by number-one
   artists are the strongest version of the "radio knew them and still
   buried this" story.

## Slice the charts by an angle you haven't used yet

3. **By decade.** A CASE ladder on `chart_week` buckets entries into
   decades (`WHEN chart_week >= '2020' THEN '2020s'` and so on — the
   dates are text, but they sort correctly). Which decade had the most
   one-week visitors? The most long-haul hits?
4. **One-hit wonders as their own roster.** The walkthrough found that
   57% of all charting artists charted exactly one song. Build that
   table (`HAVING COUNT(*) = 1`) and find the one-hit wonders whose
   single visit still peaked in the top 10.
5. **The grind list.** Using `artist_songs`, find songs with the most
   total weeks on chart that never cracked the top 40 — radio played
   them forever without ever pushing them. That's a different kind of
   buried.

## Ask a new question of the same data

6. **Songs per decade of a career.** Pick any long-career artist in
   `known_artists` and chart their songs-per-decade with a GROUP BY.
   Career arcs in one query.
7. **Collaboration rates over time.** The raw `performer` credits still
   hold every "Featuring". Count credits containing
   `' Featuring '` per decade. When did the featuring economy actually
   take off?
8. **Re-run the whole pipeline on a new snapshot.** The Last.fm numbers
   change daily and the fetch script stamps its output with a date. Pull
   a fresh snapshot in a month and diff your gem list against the old
   one. Which gems were stable and which were a moment in time?

## Make it yours

The real graduation exercise: pick a question this README never asked,
write the query yourself, and add your finding to your own fork's README
with one sentence on why the threshold you picked is defensible. That last
sentence — defending a number — is the analyst skill everything here has
been building toward.
