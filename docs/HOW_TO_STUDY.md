# How to Study the Query File

The wall-to-wall comments in `queries/hidden_gems.sql` are a LEARNING SCAFFOLD,
not how real work is commented. Two modes:

- **Learning:** keep the read-out-loud comments and rehearse them (method below).
- **Portfolio / industry:** strip to standard light comments, intent plus
  anything non-obvious. A comment on every obvious line is a red flag in
  professional code. Knowing when to comment heavily vs lightly is itself a sign
  of experience.

## The method: rehearse, don't just retype

1. Take one small section at a time.
2. Type and quietly SAY the read-out-loud comment
   ("SELECT every column... FROM the chart_entries table...").
3. Repeat the section until you can say the narration out loud SMOOTHLY, no
   stumbling. Fluency means it clicked; stumbling shows the exact gap to revisit.
4. THEN read and run the SQL; it now reads as the answer to a sentence you can
   already say.
5. LEVEL UP: hide the SQL and rebuild the query from the comment alone.

## Why it works (real learning science)

- **Self-explanation:** narrating a step in your own words deepens understanding;
  smooth means you get it, halting shows the gap.
- **Generation effect** (Slamecka & Graf 1978, ~d=0.40): producing beats reading.
- **Retrieval practice** (Roediger & Karpicke 2006): recalling beat re-reading
  61% vs 40% at one week, which is why step 5 is the highest-value step.
- Plus immediate feedback (running each section) and motor fluency (typing the
  parens, quotes, and keywords until they are automatic). Bonus: you can talk
  fluently about code you generated, which is interview-ready.
