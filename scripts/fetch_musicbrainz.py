# =====================================================================
# STEP 46: FETCH REAL RELEASE YEARS FROM THE MUSICBRAINZ API
# WHY: Last.fm never returned a release year, so every gem's decade so
#      far is the ARTIST'S debut decade, not the SONG's. MusicBrainz is
#      a free, open music database that DOES know release dates. This
#      script asks it, for each gem, "when was this recording first
#      released?" and keeps the earliest year it can confidently find.
#      Step 47 blends that real year with the debut decade (COALESCE).
# NOTE: Second API of the project, and it behaves differently from
#      Last.fm:
#      - NO API KEY. MusicBrainz is open. But it REQUIRES a User-Agent
#        header naming the app and a contact, or it answers 403. That
#        is its version of "identify yourself".
#      - Rate limit is strict: ONE request per second. time.sleep(1.1)
#        stays under it. A 16-gem test is about 18 seconds.
#      Python comments start with # the way SQL comments start with --.
# RESULT: (pending)
# =====================================================================
#
# READ OUT LOUD, top to bottom:
# -- IMPORTS: built-in toolkits only, no installs (same set fetch_lastfm
#    used): csv, json, sqlite3, sys, time, urllib.
# -- USER_AGENT: the app + contact string MusicBrainz demands. Without
#    it, every request is refused with 403.
# -- WORK LIST: open music_gems.db and SELECT the top-K gems PER DECADE
#    from gem_decade (ROW_NUMBER over PARTITION BY debut_decade, best
#    decade_score first, keep rank <= K). K is the number typed after
#    the script name. A small K is a spread-out sample for testing; a
#    big K is the real candidate pool. No number defaults to K=2.
# -- LOOP: for each gem, build a MusicBrainz recording-search URL asking
#    for recordings where the artist matches AND the title matches, send
#    it (carrying the User-Agent), and decode the JSON reply.
# -- MATCH RULE: among returned recordings scoring 90+ (a confident name
#    match), gather every release date, take the 4-digit year off each,
#    and keep the EARLIEST -- a song's first release, ignoring later
#    reissues and compilations. No 90+ match = no year, and that gem
#    will fall back to its debut decade when Step 47 blends.
# -- POLITENESS: time.sleep(1.1) after every request = under 1/second.
# -- ERRORS: MusicBrainz sometimes answers 503 (busy/throttled); the
#    fetch retries with a growing pause before giving up. Any request
#    that still fails logs and moves on; one bad row never kills a run.
# -- OUTPUT: write data\mb_years_2026-07-20.csv (artist, track,
#    debut_decade, release_year, release_decade, mb_score, matched),
#    then print an overall match rate and a per-decade breakdown
#    (older decades are the ones most likely to miss).
# -- TEST MODE: ALWAYS run a small K first ("...py 2" = 2 per decade,
#    16 gems) to prove the User-Agent, URL, and parsing work, and to
#    read the match rate, BEFORE committing to the full candidate run.
# =====================================================================

import csv
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DB_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\music_gems.db"
OUT_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\mb_years_2026-07-20.csv"
USER_AGENT = "MusicHiddenGemsByDecade/1.0 ( https://github.com/michaelnocito )"
MIN_SCORE = 90

k = int(sys.argv[1]) if len(sys.argv) > 1 else 2
if len(sys.argv) <= 1:
    print(f"TEST MODE: no number given, using K={k} per decade")
print(f"Fetching top {k} gems per decade")

conn = sqlite3.connect(DB_FILE)
worklist = conn.execute(
    """
    SELECT debut_decade, artist, track
    FROM (SELECT debut_decade, artist, track,
                 ROW_NUMBER() OVER (PARTITION BY debut_decade
                                    ORDER BY decade_score DESC) AS rk
          FROM gem_decade)
    WHERE rk <= ?
    ORDER BY debut_decade, rk
    """,
    (k,),
).fetchall()
conn.close()
print(f"Work list: {len(worklist)} gems")


def earliest_year(recordings):
    years = []
    for rec in recordings:
        if int(rec.get("score", 0)) < MIN_SCORE:
            continue
        frd = rec.get("first-release-date", "")
        if frd[:4].isdigit():
            years.append(int(frd[:4]))
        for rel in rec.get("releases", []):
            d = rel.get("date", "")
            if d[:4].isdigit():
                years.append(int(d[:4]))
    return min(years) if years else None


def best_score(recordings):
    return max((int(r.get("score", 0)) for r in recordings), default=0)


def fetch_recordings(url):
    # MusicBrainz answers 503 when it is busy or thinks we are too fast.
    # Wait a growing pause and retry a few times before giving up on a
    # gem, so a single throttle never loses a row.
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp).get("recordings", [])
        except urllib.error.HTTPError as e:
            if e.code == 503 and attempt < 3:
                time.sleep(2 * (attempt + 1))   # 2s, then 4s, then 6s
                continue
            raise
    return []


per_decade = {}   # debut_decade -> [matched, total]
matched_total = 0

with open(OUT_FILE, "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out)
    writer.writerow(["artist", "track", "debut_decade",
                     "release_year", "release_decade", "mb_score", "matched"])

    for i, (decade, artist, track) in enumerate(worklist, start=1):
        # strip any double quotes so they cannot break the Lucene query
        qa = artist.replace('"', " ")
        qt = track.replace('"', " ")
        query = f'artist:"{qa}" AND recording:"{qt}"'
        params = urllib.parse.urlencode({"query": query, "fmt": "json", "limit": 100})
        url = "https://musicbrainz.org/ws/2/recording?" + params

        year = None
        score = 0
        try:
            recordings = fetch_recordings(url)
            score = best_score(recordings)
            year = earliest_year(recordings)
        except Exception as e:
            print(f"  FAILED: {artist} - {track} ({e})")

        rel_decade = f"{str(year)[:3]}0s" if year else ""
        matched = 1 if year else 0
        matched_total += matched
        stats = per_decade.setdefault(decade, [0, 0])
        stats[0] += matched
        stats[1] += 1

        writer.writerow([artist, track, decade, year or "",
                         rel_decade, score, matched])
        flag = rel_decade if year else "no confident match"
        print(f"[{i}/{len(worklist)}] {decade}  {artist} - {track}  ->  {flag} (score {score})")

        time.sleep(1.1)

print()
print(f"MATCHED {matched_total} of {len(worklist)} "
      f"({round(100 * matched_total / len(worklist))}%)")
print("Per decade (matched / total):")
for decade in sorted(per_decade):
    m, t = per_decade[decade]
    print(f"  {decade}: {m}/{t}")
print(f"Wrote {OUT_FILE}")
