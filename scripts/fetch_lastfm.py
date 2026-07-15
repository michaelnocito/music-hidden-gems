# =====================================================================
# STEP 16: FETCH LISTENER-LOVE DATA FROM THE LAST.FM API
# WHY: The chart tables only say what radio rewarded. To find what
#      listeners loved, each known artist's top tracks are pulled from
#      Last.fm, with two numbers per track: playcount (total plays)
#      and listeners (unique people). Playcount divided by listeners
#      is the love-per-listener signal the gem query will rank on.
# NOTE: This is the project's one Python file. SQL cannot call the
#      internet, so a script collects the data; its CSV goes back
#      into the database and everything after is SQL again. Python
#      comments start with # the way SQL comments start with --.
# RESULT: (pending)
# =====================================================================
#
# READ OUT LOUD, top to bottom:
# -- IMPORTS: only Python's built-in toolkits (no installs) --
#    csv       writes the output spreadsheet file
#    json      decodes Last.fm's replies (APIs answer in JSON text)
#    sqlite3   reads the roster straight from music_gems.db
#    time      pauses between requests (politeness / rate limiting)
#    urllib    makes the actual web requests to the API
# -- KEY: read the API key from its own file (pull from lastfm_api_key.txt)
#    Keys never get typed into code. Code gets shared; key files get
#    ignored. .strip() trims invisible spaces/newlines around the key.
# -- ROSTER: open the database, SELECT every primary_artist FROM
#    known_artists (pull from music_gems.db) -- the same 1,570 names
#    the walkthrough built, no retyping, no copy-paste drift.
# -- LOOP: for each artist, build a request URL for the
#    artist.gettoptracks endpoint (an endpoint is one named question
#    the API knows how to answer), send it, decode the JSON reply,
#    and keep 4 fields per track: artist, track name, playcount,
#    listeners. limit=50 asks for at most 50 tracks per artist.
# -- POLITENESS: time.sleep(0.25) after every request = max 4
#    requests per second. APIs ban clients that hammer them.
# -- ERRORS: if one artist's request fails, log it and move on.
#    One bad name must not kill a 25-minute run.
# -- OUTPUT: write every row to data\lastfm_tracks_2026-07-14.csv
#    (display: progress prints every 50 artists so you can see life)
#    The date in the filename matters: Last.fm numbers change daily,
#    so the file records WHEN this snapshot was taken.
# -- TEST MODE: a number typed after the script name limits the run
#    to that many artists (sys.argv reads it). "fetch_lastfm.py 3"
#    = 3 artists, a 5-second proof the key and URL work. No number
#    = the full roster. Never point a brand-new script at a full
#    25-minute run; prove it on a sample first, same as previewing
#    a CASE rule on real rows before building a table with it.
# =====================================================================

import csv
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

KEY_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\lastfm_api_key.txt"
DB_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\music_gems.db"
OUT_FILE = r"C:\Users\Mike\Projects\music-hidden-gems\data\lastfm_tracks_2026-07-14.csv"

with open(KEY_FILE) as f:
    api_key = f.read().strip()

conn = sqlite3.connect(DB_FILE)
roster = [row[0] for row in conn.execute(
    "SELECT primary_artist FROM known_artists ORDER BY primary_artist")]
conn.close()

if len(sys.argv) > 1:
    roster = roster[:int(sys.argv[1])]
    print(f"TEST MODE: limiting to {len(roster)} artists")

print(f"Roster loaded: {len(roster)} artists")

failed = []
rows_written = 0

with open(OUT_FILE, "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out)
    writer.writerow(["artist", "track", "playcount", "listeners"])

    for i, artist in enumerate(roster, start=1):
        params = urllib.parse.urlencode({
            "method": "artist.gettoptracks",
            "artist": artist,
            "api_key": api_key,
            "format": "json",
            "limit": 50,
        })
        url = "https://ws.audioscrobbler.com/2.0/?" + params

        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.load(resp)
            for track in data.get("toptracks", {}).get("track", []):
                writer.writerow([
                    artist,
                    track.get("name", ""),
                    track.get("playcount", ""),
                    track.get("listeners", ""),
                ])
                rows_written += 1
        except Exception as e:
            failed.append(artist)
            print(f"  FAILED: {artist} ({e})")

        if i % 50 == 0:
            print(f"{i}/{len(roster)} artists done, {rows_written} tracks so far")

        time.sleep(0.25)

print(f"DONE: {rows_written} tracks from {len(roster) - len(failed)} artists")
print(f"Failed artists: {len(failed)}")
for name in failed:
    print(f"  {name}")
