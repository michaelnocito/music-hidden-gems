# =====================================================================
# STEP 36: ENRICH THE TOP 500 GEMS -- ALBUM, GENRE TAGS, DURATION
# WHY: The gem list is stronger as a browsable, sortable page with
#      album, genre, and duration columns. Last.fm's track.getInfo
#      endpoint returns all three in one call per track, so this
#      script walks the frozen top_gems table (500 rows) and writes
#      one enrichment row per gem. At 4 requests/second this is a
#      ~3 minute run, not a 25 minute one.
# NOTE: genre comes from Last.fm's community TAGS (the top few tags
#      listeners applied). Tags are folk categories, not a strict
#      taxonomy -- 'k-pop', 'country', '60s' may all appear. The top
#      3 are kept, pipe-separated, and the first tag serves as the
#      primary genre for sorting.
# FALLBACK (added after the first full run): track-level tags exist
#      for only ~3% of hidden gems -- obscure tracks don't accumulate
#      tags. When a track has none, the ARTIST's top tags are used
#      instead (artist.gettoptags), fetched once per artist and
#      cached in a dictionary so repeat artists cost no extra calls.
#      "Genre of the artist" is the honest reading of the column.
# RESULT: (pending)
# =====================================================================
#
# READ OUT LOUD, top to bottom:
# -- KEY + ROSTER: read the API key from its file; read the 500
#    frozen gems (artist, track) straight from top_gems in the
#    database (pull from music_gems.db).
# -- LOOP: for each gem, call the track.getInfo endpoint with the
#    artist and track name. From the reply keep:
#      album     the album title the track belongs to (if any)
#      tags      the top 3 community tags, joined with |
#      duration  track length in milliseconds ('0' when unknown,
#                converted to m:ss at import time, not here --
#                raw data stays raw)
# -- POLITENESS: time.sleep(0.25) between requests, as always.
# -- ERRORS: a failed track is logged and skipped; its enrichment
#    columns stay empty rather than killing the run.
# -- OUTPUT: data\gem_details_2026-07-15.csv, dated because tags
#    and stats drift over time. One row per gem: artist, track,
#    album, tags, duration_ms.
# =====================================================================

# -- TEST MODE: a number typed after the script name limits the run
#    to that many gems ("fetch_lastfm_details.py 3" = 3 gems, a
#    5-second proof). No number = all 500.

import csv
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

KEY_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\lastfm_api_key.txt"
DB_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\music_gems.db"
OUT_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\gem_details_2026-07-15.csv"

with open(KEY_FILE) as f:
    api_key = f.read().strip()

conn = sqlite3.connect(DB_FILE)
roster = list(conn.execute(
    "SELECT artist, track FROM top_gems ORDER BY plays_per_listener DESC"))
conn.close()

if len(sys.argv) > 1:
    roster = roster[:int(sys.argv[1])]
    print(f"TEST MODE: limiting to {len(roster)} gems")

print(f"Gems loaded: {len(roster)}")

failed = []
rows_written = 0
artist_tag_cache = {}


def artist_tags(artist):
    # one artist.gettoptags call per DISTINCT artist, cached
    if artist not in artist_tag_cache:
        params = urllib.parse.urlencode({
            "method": "artist.gettoptags",
            "artist": artist,
            "api_key": api_key,
            "format": "json",
        })
        url = "https://ws.audioscrobbler.com/2.0/?" + params
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.load(resp)
            tag_list = data.get("toptags", {}).get("tag", [])
            artist_tag_cache[artist] = "|".join(
                t.get("name", "") for t in tag_list[:3])
        except Exception:
            artist_tag_cache[artist] = ""
        time.sleep(0.25)
    return artist_tag_cache[artist]

with open(OUT_FILE, "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out)
    writer.writerow(["artist", "track", "album", "tags", "duration_ms"])

    for i, (artist, track) in enumerate(roster, start=1):
        params = urllib.parse.urlencode({
            "method": "track.getInfo",
            "artist": artist,
            "track": track,
            "api_key": api_key,
            "format": "json",
        })
        url = "https://ws.audioscrobbler.com/2.0/?" + params

        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.load(resp)
            info = data.get("track", {})
            album = info.get("album", {}).get("title", "")
            tag_list = info.get("toptags", {}).get("tag", [])
            tags = "|".join(t.get("name", "") for t in tag_list[:3])
            if not tags:
                tags = artist_tags(artist)
            duration = info.get("duration", "0")
            writer.writerow([artist, track, album, tags, duration])
            rows_written += 1
        except Exception as e:
            failed.append(track)
            writer.writerow([artist, track, "", "", "0"])
            print(f"  FAILED: {artist} - {track} ({e})")

        if i % 50 == 0:
            print(f"{i}/{len(roster)} gems done")

        time.sleep(0.25)

print(f"DONE: {rows_written} enriched, {len(failed)} failed")
for name in failed:
    print(f"  {name}")
