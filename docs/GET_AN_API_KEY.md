# Get a Last.fm API Key (and Why APIs Matter to Analysts)

The chart data in this project came from a CSV file someone else prepared. The
listener data comes from a live API, which is how a huge share of real-world
analyst data arrives. This doc gets you from zero to a working key in about
five minutes, and explains each idea along the way.

## What an API is

An API (Application Programming Interface) is a website built for programs
instead of people. You visit `last.fm/music/Prince` and get a styled page;
a script visits `ws.audioscrobbler.com/2.0/?method=artist.gettoptracks&artist=Prince...`
and gets raw data back. Same information, machine-readable format.

Three terms you will see everywhere:

- **Endpoint** — one named question the API knows how to answer.
  `artist.gettoptracks` is an endpoint: "give me this artist's most-played
  tracks." APIs publish a list of their endpoints; that list is the menu.
- **JSON** — the text format the answer comes back in. Nested labels and
  values, like `{"name": "Purple Rain", "playcount": "9541320"}`. Python
  reads it natively.
- **Rate limit** — how fast you are allowed to ask. Hammer an API and it
  will slow you down or ban your key. The fetch script in this repo pauses
  a quarter second between requests, which keeps it well inside polite range.

## What an API key is

A key is a long random string that identifies YOUR requests. The API uses it
to know who is asking, enforce rate limits per person, and shut off abusers
without shutting off everyone. Think of it as a library card: free to get,
but yours, and you don't lend it out.

## Get your key

1. Create a free account at [last.fm](https://www.last.fm) if you don't have one, and log in.
2. Go to [last.fm/api/account/create](https://www.last.fm/api/account/create).
3. Fill the form:
   - **Contact email** — your email.
   - **Application name** — anything, e.g. `music-hidden-gems`.
   - **Application description** — e.g. `personal data analysis project`.
   - **Callback URL** and **Application homepage** — leave blank. Those are
     for apps that log users in; this project only reads public data.
4. Submit. The next page shows your **API key**, a 32-character string.
   (It also shows a "shared secret" — not needed for read-only use.)

If the page shows a firewall error, log in to last.fm first, then retry the
API page in the same tab; a private/incognito window or different network
also clears it.

## Store the key the professional way

Never paste a key into source code. Code gets shared, committed, and posted;
a key inside it leaks the moment the repo goes public. The pattern used here:

1. Put the key on a single line in a file named `lastfm_api_key.txt` at the
   root of this project (next to this repo's README).
2. That filename is listed in `.gitignore`, so git will never commit it.
3. The fetch script reads the file at runtime:

   ```python
   with open(KEY_FILE) as f:
       api_key = f.read().strip()
   ```

The code that gets published never contains a secret, and anyone who clones
the repo supplies their own key by creating their own one-line file. This
same pattern (secrets in ignored files or environment variables, read at
runtime) is standard in professional data work.

## Run the fetch script

With the key file in place, the data pull is `scripts/fetch_lastfm.py`. Run it
from PowerShell (or any terminal) at the project root:

```powershell
cd path\to\music-hidden-gems
py scripts\fetch_lastfm.py 3
```

**Always test before the full pull.** The number after the script name is a
test switch: `3` fetches only the first 3 artists, which proves in five
seconds that your key is accepted and real data lands in the CSV. Expect
`DONE: ~150 tracks from 3 artists` and `Failed artists: 0`. Pointing a
brand-new script at a 25-minute run without a sample test first is how you
find a typo at minute 24.

Then run it with no number for the full roster:

```powershell
py scripts\fetch_lastfm.py
```

Expect `Roster loaded: 1570 artists`, a progress line every 50 artists, and
roughly 20 to 30 minutes of runtime (the script deliberately pauses between
requests to stay polite to the API). If `py` is not recognized on your
system, use `python` instead.

**One trap worth knowing (it will bite you eventually):** the script reads
the database FILE on disk. DB Browser holds your changes in a temporary
journal until you click **Write Changes** — so a table you just created can
be visible in DB Browser and invisible to the script at the same time. If
the script says `no such table`, go back to DB Browser and click Write
Changes. Two programs, one file: only committed changes are shared.

## If a key ever leaks

Keys can be revoked and reissued from the provider's site. Leaked a key?
Delete it there, generate a new one, update your key file. The code never
changes, which is another payoff of keeping keys out of source.
