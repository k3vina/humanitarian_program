# Humanitarian Programme Data Analysis

An SQL project analysing data from a humanitarian programme that works across regions, districts and villages in Somalia. It looks at how many people each partner organisation reaches, which villages they serve, where partners overlap, and how reach compares with village and district populations.

**Stack:** PostgreSQL 16 · Docker · DBeaver

---

## Project files

| File | Contents |
|---|---|
| `humanitarian_program.sql` |: table creation, sample data, foundational queries (Tasks 1–7) |
| `humanitarian_program_week2.sql` |: advanced SQL: HAVING, UNION, subqueries, CTEs, window functions, views, triggers, stored procedures and challenges |
| `README.md` | This file |

---

## The data

Three tables in the `humanitarian_program` database:

| Table | Description | Keys |
|---|---|---|
| `village_locations` | 14 villages with coordinates and total population | `village_id` PK, `village` UNIQUE |
| `beneficiary_partner_data` | 18 records of partner activity: partner, village, beneficiary count and type | `partner_id` PK, `village` FK → `village_locations.village` |
| `jurisdiction_hierarchy` | Administrative structure: Region → District → Village | `id` PK, `parent_id` FK → `id` (self-reference) |

**Partners:** World Vision, CARE, IRC
**Regions:** Middle Shabelle, Hiraan
**Districts:** Balcad, Jowhar (Middle Shabelle), Beledweyn (Hiraan)

---

## Setup

### 1. Start PostgreSQL in Docker

```bash
docker run --name pg-humanitarian -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:postgres
```

### 2. Connect DBeaver

New Connection → PostgreSQL
- Host: `localhost` · Port: `5432`
- Database: `postgres` · User: `postgres` · Password: `postgres`

### 3. Create the database

Run this on its own while connected to `postgres`:

```sql
CREATE DATABASE humanitarian_program;
```

Refresh the connection, then open a new SQL editor on `humanitarian_program`.

### 4. Run the scripts in order

1. `humanitarian_program.sql`: run the whole script with **Alt+X** (Execute Script)
2. `humanitarian_program_week2.sql`: run the whole script with **Alt+X**

> Use **Alt+X**, not Ctrl+Enter. Ctrl+Enter runs only the statement under the cursor. Each `SELECT` opens in its own results tab.

Both scripts can be rerun safely: they drop and recreate their own objects.

---

## Task A: Foundational SQL

| Task | What it does | SQL used |
|---|---|---|
| 1. Explore | View all tables, filter villages over 4,500 people and household records | `SELECT`, `WHERE` |
| 2. Convert counts | Convert households to individuals (× 6) | `CASE WHEN` |
| 3. Partner analysis | Total beneficiaries, villages served and average per record for each partner | `GROUP BY`, `SUM`, `COUNT(DISTINCT)`, `AVG` |
| 4. Village coverage | Beneficiaries as a percentage of village population | `JOIN` |
| 5. District info | Link each record to its district | Self-join |
| 6. Multi-partner villages | Villages served by more than one partner | `HAVING` |
| 7. Summary tables | `Partner_summary` and `District_summary` | `CREATE TABLE AS SELECT` |

## Task B: Advanced SQL

| Task | What it does | SQL used |
|---|---|---|
| 1. Advanced aggregation | Partners over 5,000 beneficiaries, multi-partner villages, partners in more than 3 villages, districts over 10,000 | `GROUP BY`, `HAVING`, `CASE WHEN` |
| 2. Combining queries | All villages with their partners, plus villages with no activity | `UNION`, `UNION ALL`, `NOT EXISTS` |
| 3. Subqueries | Villages and partners above the average | Derived tables, scalar subqueries |
| 4. CTEs | District analysis: population, beneficiaries, coverage, partners | `WITH` |
| 5. Window functions | Partner ranking, district ranking within regions, top partner per district | `RANK()`, `ROW_NUMBER()`, `PARTITION BY` |
| 6. Views | Reusable `district_summary` and `partner_summary` views | `CREATE VIEW` |
| 7. Triggers | Block negative beneficiary values; log every insert | `BEFORE` / `AFTER INSERT` triggers, PL/pgSQL |
| 8. Stored procedures | `GetPartnerReport(name)` and `GetDistrictImpact(name)` | Functions with `RETURNS TABLE` |
| Challenges | Top partner per district, above-average district coverage, dominant partners | Window functions, subqueries |

### Calling the report procedures

```sql
SELECT * FROM GetPartnerReport('World Vision');
SELECT * FROM GetDistrictImpact('Jowhar');
```

Names are matched without regard to case. An unknown name returns no rows.

---

## Key results

### Partners

| Partner | Individual beneficiaries | Villages | Districts | Rank |
|---|---|---|---|---|
| World Vision | 13,600 | 5 | 2 | 1 |
| CARE | 9,150 | 6 | 2 | 2 |
| IRC | 9,000 | 6 | 2 | 3 |

### Districts

| Region | District | Population | Individual beneficiaries | Coverage | Partners |
|---|---|---|---|---|---|
| Middle Shabelle | Balcad | 13,000 | 11,250 | 86.54% | 3 |
| Middle Shabelle | Jowhar | 52,858 | 20,500 | 38.78% | 3 |
| Hiraan | Beledweyn | 0 | 0 | none | 0 |

### Findings

- **World Vision reaches the most people** and is the only partner above the average partner total (10,583).
- **Three villages are served by more than one partner:** Dharkenley, Bulo-Kahin and Hilo Kelyo.
- **Balcad district is well covered (86.54%); Jowhar is not (38.78%)**, even though Jowhar has the most beneficiaries in total, because its population is four times larger.
- **Beledweyn has no recorded activity.** It exists in the hierarchy but has no villages or partner records, which is a coverage gap.
- **World Vision leads in Balcad (66.67% of beneficiaries); IRC leads in Jowhar (39.51%).** CARE is not the top partner in any district.
- **Data quality flag:** Dharkenley shows **124% coverage**, with 6,200 beneficiaries against a population of 5,000. This suggests partners may be counting the same people, or the 6-people-per-household estimate is too high for this village.

---

## Assumptions and design decisions

- **Household conversion:** `Households` × 6 = individual beneficiaries; `Individuals` are used as recorded.
- **"Balcad" is both a district and a village.** Every join to `jurisdiction_hierarchy` filters `type = 'Village'` so the district row is never matched by mistake.
- **No double-counting of population:** District population is the sum of each village's population counted once, calculated separately from the beneficiary records (Dharkenley alone has three records).
- **All districts are shown:** District summaries start from the district list and use `LEFT JOIN`, so districts with no activity appear as 0 instead of disappearing.
- **Village coverage (Task B)** combines all partners in a village before comparing with the average.
- **Average beneficiaries** in the partner summary is per record, not per village.
- **Task A tables replaced by Task B views:** `district_summary` and `partner_summary` were tables in Task A and become views in Task B, so they always reflect current data.
- **Stored procedures are PostgreSQL functions.** `CREATE PROCEDURE` in PostgreSQL cannot return a result set to a `SELECT`, so the reports use `CREATE FUNCTION ... RETURNS TABLE`.
- **Dominant partner** means the partner with the largest share of a district's beneficiaries, not necessarily a majority.
- **Trigger tests clean up after themselves.** The test insert is deleted so it does not change the results; its log entry is kept in `beneficiary_insert_log`.

---

## Notes

- PostgreSQL converts unquoted names to lowercase, so `Partner_summary` appears as `partner_summary` in DBeaver.
- Coverage uses `* 100.0` (not `* 100`) to force decimal division; integer division would round most values down to 0.
- Trigger test messages appear in DBeaver's **Output** tab.
