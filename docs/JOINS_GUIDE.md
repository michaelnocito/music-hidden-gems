# Joins, Explained From Zero

A standalone guide for beginners. No prior join knowledge assumed, but by the end
this covers everything a working analyst actually uses: what joins are, the keys
they run on, every join type, and how the industry structures data around them.

## 1. The problem joins solve

A well-run database never stores the same fact twice. Customer names live in a
`customers` table. Orders live in an `orders` table. Song chart history lives in
one table, listener statistics in another. This separation (called
**normalization**) keeps data clean: update a customer's address in one place and
every report agrees.

The cost of that cleanliness: no single table can answer a real question.
"Which songs did radio bury but listeners love?" needs the chart table AND the
listener table at once. A **JOIN** is the operation that combines rows from two
tables into wider rows, matched up by a shared value.

## 2. Keys: the values joins match on

### Primary keys

A **primary key** is the column (sometimes a combination of columns) that uniquely
identifies each row in its own table. One row, one key, no duplicates, never
empty. Examples:

- `customers.customer_id` - each customer gets exactly one ID
- Steam's `AppID` - each game has exactly one
- A songs table might use `song_id`

The table that owns the primary key is the authority on that thing. If you want
to know about customer 4417, there is exactly one row that answers.

### Foreign keys

A **foreign key** is a column in a DIFFERENT table that stores another table's
primary key values. It is how one table points at another.

```
customers                     orders
-----------------             -------------------------------
customer_id  name             order_id  customer_id  total
1            Aretha           501       2            19.99
2            Marvin           502       2            5.00
3            Otis             503       1            12.50
```

`orders.customer_id` is a foreign key. Read order 502 and it says "I belong to
customer 2." Look up 2 in `customers` (where it is the primary key) and you learn
that's Marvin.

The differences that matter:

| | Primary key | Foreign key |
|---|---|---|
| Lives in | its own table | the *other* table |
| Uniqueness | every value unique | values repeat freely |
| Job | identify this row | point at a row elsewhere |
| Example above | `customers.customer_id` | `orders.customer_id` |

Repetition is the point: Marvin placed two orders, so customer_id 2 appears twice
in `orders` and exactly once in `customers`. This is a **one-to-many
relationship** (one customer, many orders), and it is the most common shape in
all of data work. The foreign key always lives on the "many" side.

A foreign key is a *promise*: every `customer_id` in `orders` should exist in
`customers`. Formal databases can enforce that promise and reject bad rows.
Real-world analyst data (CSV downloads, API pulls) enforces nothing, so part of
the job is *checking* how well the promise holds. That check is called measuring
the **match rate**, and broken promises (an order pointing at a customer that
does not exist) are called **orphans**.

## 3. How a join actually thinks

Mental model: the database walks through one table row by row. For each row it
asks the other table, "do you have rows whose key matches mine?" Each match
produces one combined output row with columns from both tables.

```sql
SELECT orders.order_id, customers.name, orders.total
FROM orders
INNER JOIN customers
       ON orders.customer_id = customers.customer_id;
```

The `ON` clause is the matching rule. Result: every order, now wearing its
customer's name.

If a key matches multiple rows on the other side, you get multiple output rows.
Join one customer to their three orders: three rows. This means **joins can grow
your row count**, a classic source of silently wrong numbers. Always know which
side is "one" and which is "many" before trusting a count or a sum after a join.

## 4. The join types

**INNER JOIN** - keep a row only if the other table matched. Unmatched rows from
either side vanish silently. Use when the question is about things that exist in
both worlds.

**LEFT JOIN** - keep EVERY row from the left (first-named) table. Where the right
table had no match, its columns come back as NULL (empty). Use when the left
table is your full population and the right table is optional extra info.

**Anti-join** - the payoff trick built on LEFT JOIN: keep only the rows where the
right side came back NULL.

```sql
SELECT customers.name
FROM customers
LEFT JOIN orders ON orders.customer_id = customers.customer_id
WHERE orders.order_id IS NULL;
```

Read out loud: keep every customer, attach their orders if any, then keep only
the customers whose order side is empty. Result: customers who never ordered.
Finding what is MISSING from a table is one of the most valuable questions in
analytics (churned users, unsold products, songs radio never played), and the
anti-join is how it is asked.

### ON pairs; WHERE filters

The two clauses look interchangeable but do different jobs, and the difference
is the whole engine of the anti-join above:

- **ON is the pairing rule.** It defines which right-table row counts as "the
  match" for a left-table row. Think of a wedding seating chart: ON is the rule
  for who sits together, not a rule for who gets into the room. With a LEFT
  JOIN, a left row that finds no partner is NOT thrown away -- it stays, with
  NULLs where its partner's columns would have been (an empty chair).
- **WHERE is the survival rule.** It runs AFTER the pairing and decides which
  finished rows appear in the result. `WHERE right.id IS NULL` means "keep only
  the rows with an empty chair" -- that one line turns a LEFT JOIN into an
  anti-join.

Because ON decides pairing and WHERE decides survival, moving a condition from
one to the other CHANGES THE ANSWER in a LEFT JOIN. A test like
`orders.status = 'paid'` inside ON means "only paid orders count as a match"
(customers keep their seat, unpaid orders just do not sit with them); the same
test in WHERE throws away every customer whose order side is NULL or unpaid --
silently deleting the unmatched customers the LEFT JOIN existed to keep.

### Compound keys: when one column is not enough to mean "the same"

A join can pair on several conditions at once:

```sql
LEFT JOIN song_keys AS s
  ON t.artist_key = s.artist_key
 AND t.title_key = s.title_key
```

The AND here is not a filter -- it is a stricter definition of "the same."
Artist alone would pair a song with EVERY song by that artist; title alone
would pair it with every other artist's song of the same name (covers are
common). Only artist AND title together identify one song. Whenever no single
column uniquely identifies the real-world thing, the pairing rule uses as many
columns as it takes; that set is called a compound (or composite) key.

**RIGHT JOIN** - mirror image of LEFT (keep every right-side row). Rarely written
in practice; analysts just reorder the tables and use LEFT. SQLite does not even
support it (nor FULL) in older versions.

**FULL OUTER JOIN** - keep everything from both sides, NULLs where either lacked
a match. Used for reconciliation ("what is in system A, system B, or both?").

**CROSS JOIN** - every row paired with every row, no key at all. 1,000 x 1,000 =
1,000,000 rows. Almost always a mistake unless you deliberately need every
combination (like building a calendar grid).

**Self-join** - a table joined to itself (with two aliases), e.g. matching each
employee row to their manager's row in the same employees table.

## 5. Joins in the industry

- **Lookup/dimension tables.** Real datasets store codes (`store_id 12`,
  `genre_id 4`) and joins pull in the human-readable names from small lookup
  tables. In warehouse work this is the "star schema": one big fact table
  (sales, plays, clicks) joined out to dimension tables (stores, dates,
  products). Most production dashboards are one fact table + several joins.
- **Text keys are second-class but common.** Clean systems join on ID numbers.
  Analysts stitching together outside sources (a chart CSV and an API pull)
  often have only names and titles. Text keys are messy ("Beyonce" vs
  "Beyoncé", "(Remastered)" suffixes), so real work normalizes the text
  (LOWER, TRIM, stripping punctuation) and then MEASURES the match rate before
  trusting any downstream result.
- **Indexes make joins fast.** A join on an un-indexed key column of a large
  table forces the database to scan the whole table for every probe.
  `CREATE INDEX` builds a lookup structure (like a book index) on the key
  column; on multi-million-row tables the same join drops from minutes to
  seconds.
- **Row-count discipline.** Professionals sanity-check counts before and after
  every join. If 581 gems go into a join and 640 rows come out, the right side
  had duplicate keys and every later aggregate is inflated.

## 6. Vocabulary recap

| Term | Meaning |
|---|---|
| Normalization | storing each fact once, in its own table |
| Primary key | column that uniquely identifies rows in its own table |
| Foreign key | column that stores another table's primary key values |
| One-to-many | one row on side A relates to many on side B (FK lives on B) |
| ON clause | the matching rule of a join |
| Match rate | % of rows that found a partner across the join |
| Orphan | a foreign key value with no matching primary key row |
| Anti-join | LEFT JOIN + IS NULL, finds what is missing |
| Fact / dimension | big event table / small descriptive lookup tables |
