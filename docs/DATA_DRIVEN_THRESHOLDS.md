# Data-Driven Thresholds: How This Project Picks Its Cutoffs

Every analysis needs cutoffs, and this project refuses to guess them. This
doc records the method and the reasoning, so every threshold in the queries
has a paper trail.

## The method

1. **Map the distribution first.** Before proposing any cutoff, measure how
   the values actually spread (how many artists have 1 song, 2 songs, 3...;
   how many tracks sit in each listener band).
2. **Price the candidates.** For each plausible cutoff, count what survives.
   A threshold is a decision about how much data to keep, so see the bill
   before signing.
3. **Choose with a reason attached.** The chosen number must have a
   defensible reading you can say out loud, not just a survivor count.
4. **Record the rejected options.** The numbers for the roads not taken
   stay in the file, so a reader can disagree intelligently.

## Worked example: the "known artist" roster

- Distribution (Step 12): 57% of all charting artists charted exactly ONE
  song. "Known" clearly sits above 1.
- Candidates priced (Step 13): 3+ songs keeps 2,596 artists; 5+ keeps
  1,570; 10+ keeps 740.
- Chosen: **5+** -- strict enough that radio demonstrably returned to the
  artist across a career, wide enough to leave a real gem-hunting ground,
  and 1,570 API calls is a polite data pull.

## Why ratios need a denominator floor

The gem signal is playcount / listeners. Ratios lie when the denominator is
tiny: a track 40 people played 30 times each posts a spectacular ratio that
means nothing, while a track 100,000 people replay 7 times each means a lot.
This is a general law, not a music fact: **small samples produce extreme
values as a mathematical certainty** (their variation is larger -- de
Moivre's 1730 result, popularized as "the most dangerous equation" by
Wainer, 2007). Any top-N list ranked by a ratio will be dominated by
tiny-denominator noise unless a minimum-denominator floor is applied. The
floor, like every other threshold here, is chosen from the measured
distribution of listener counts.

## References

- Wainer, H. (2007). The most dangerous equation. *American Scientist,
  95*(3), 249-256.
- Tversky, A., & Kahneman, D. (1971). Belief in the law of small numbers.
  *Psychological Bulletin, 76*(2), 105-110. (Why human intuition
  underestimates small-sample noise, which is why the floor must be
  computed, not felt.)
