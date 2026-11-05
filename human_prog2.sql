-- =====================================================================
-- HUMANITARIAN PROGRAMME DATA ANALYSIS - WEEK 2 (ADVANCED SQL)
-- PostgreSQL (Docker) + DBeaver
--
-- Runs on the Week 1 humanitarian_program database. It does NOT
-- recreate the database or the sample data.
-- In DBeaver, open a SQL editor on humanitarian_program and run the
-- whole file with Alt+X (Execute Script).
--
-- Conventions used throughout:
--   * Individual beneficiaries = beneficiaries x 6 for 'Households',
--     otherwise beneficiaries (same rule as Week 1).
--   * Villages are linked to districts through jurisdiction_hierarchy,
--     always filtering type = 'Village', because 'Balcad' is both a
--     district and a village.
-- =====================================================================


-- =====================================================================
-- TASK 1: ADVANCED AGGREGATION (GROUP BY, HAVING, CASE WHEN)
-- HAVING filters groups after aggregation; WHERE filters rows before.
-- =====================================================================

-- 1.1 Partners that have reached more than 5,000 individual beneficiaries
SELECT
    partner,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END) AS total_individual_beneficiaries
FROM beneficiary_partner_data
GROUP BY partner
HAVING SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                ELSE beneficiaries END) > 5000
ORDER BY total_individual_beneficiaries DESC;

-- 1.2 Villages served by more than one partner
SELECT
    village,
    COUNT(DISTINCT partner) AS number_of_partners,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END) AS total_individual_beneficiaries
FROM beneficiary_partner_data
GROUP BY village
HAVING COUNT(DISTINCT partner) > 1
ORDER BY number_of_partners DESC, total_individual_beneficiaries DESC;

-- 1.3 Partners operating in more than 3 villages
SELECT
    partner,
    COUNT(DISTINCT village) AS villages_served,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END) AS total_individual_beneficiaries
FROM beneficiary_partner_data
GROUP BY partner
HAVING COUNT(DISTINCT village) > 3
ORDER BY villages_served DESC;

-- 1.4 Districts with more than 10,000 individual beneficiaries
SELECT
    d.name AS district,
    SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
             ELSE b.beneficiaries END) AS total_individual_beneficiaries,
    COUNT(DISTINCT b.village) AS villages_served
FROM beneficiary_partner_data b
JOIN jurisdiction_hierarchy v ON v.name = b.village AND v.type = 'Village'
JOIN jurisdiction_hierarchy d ON d.id = v.parent_id
GROUP BY d.name
HAVING SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                ELSE b.beneficiaries END) > 10000
ORDER BY total_individual_beneficiaries DESC;


-- =====================================================================
-- TASK 2: COMBINING QUERIES (UNION / UNION ALL)
-- all_villages uses UNION to merge the village lists from BOTH tables
-- and remove duplicates, so a village that exists in only one table is
-- still included.
-- The report then uses UNION ALL to stack:
--   (a) villages WITH partner activity, one row per village + partner
--   (b) villages with NO recorded partner activity
-- UNION ALL is right here because the two parts can never overlap, so
-- there is nothing to de-duplicate.
-- With the current data, part (b) returns no rows: every village has
-- at least one partner.
-- =====================================================================
WITH all_villages AS (
    SELECT village FROM village_locations
    UNION
    SELECT name FROM jurisdiction_hierarchy WHERE type = 'Village'
)
SELECT
    av.village,
    b.partner,
    SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
             ELSE b.beneficiaries END) AS individual_beneficiaries,
    'Active' AS activity_status
FROM all_villages av
JOIN beneficiary_partner_data b ON b.village = av.village
GROUP BY av.village, b.partner

UNION ALL

SELECT
    av.village,
    NULL AS partner,
    0    AS individual_beneficiaries,
    'No recorded partner activity' AS activity_status
FROM all_villages av
WHERE NOT EXISTS (
    SELECT 1 FROM beneficiary_partner_data b WHERE b.village = av.village
)
ORDER BY village, partner;


-- =====================================================================
-- TASK 3: NESTED QUERIES / SUBQUERIES
-- =====================================================================

-- 3A. Villages whose coverage is higher than the average village coverage.
-- Beneficiaries are first added up per village across ALL partners
-- (derived table in FROM), then compared with the average of those
-- village coverages (scalar subquery in WHERE).
SELECT
    vc.village,
    vc.population,
    vc.beneficiaries,
    vc.coverage_pct
FROM (
    SELECT
        v.village,
        v.total_population AS population,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS beneficiaries,
        ROUND(SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                       ELSE b.beneficiaries END) * 100.0 / v.total_population, 2) AS coverage_pct
    FROM village_locations v
    JOIN beneficiary_partner_data b ON b.village = v.village
    GROUP BY v.village, v.total_population
) vc
WHERE vc.coverage_pct > (
    SELECT AVG(village_cov)
    FROM (
        SELECT SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                        ELSE b.beneficiaries END) * 100.0 / v.total_population AS village_cov
        FROM village_locations v
        JOIN beneficiary_partner_data b ON b.village = v.village
        GROUP BY v.village, v.total_population
    ) avg_src
)
ORDER BY vc.coverage_pct DESC;

-- 3B. Partners whose total individual beneficiaries are above the
-- average partner total.
SELECT
    pt.partner,
    pt.total_individual_beneficiaries
FROM (
    SELECT
        partner,
        SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                 ELSE beneficiaries END) AS total_individual_beneficiaries
    FROM beneficiary_partner_data
    GROUP BY partner
) pt
WHERE pt.total_individual_beneficiaries > (
    SELECT AVG(partner_total)
    FROM (
        SELECT SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                        ELSE beneficiaries END) AS partner_total
        FROM beneficiary_partner_data
        GROUP BY partner
    ) totals
)
ORDER BY pt.total_individual_beneficiaries DESC;


-- =====================================================================
-- TASK 4: CTEs (WITH) - DISTRICT-LEVEL ANALYSIS
-- Avoiding double-counting: Dharkenley has 3 beneficiary records, so
-- joining populations to beneficiary rows would add its 5,000 people
-- three times. District population is therefore calculated in its own
-- CTE straight from the village list (each village counted once), and
-- only joined to the beneficiary totals after both are aggregated.
-- LEFT JOINs keep districts with no activity (Beledweyn).
-- NULLIF avoids division by zero for a district with no population.
-- =====================================================================
WITH village_district AS (          -- every village with its district
    SELECT v.name AS village, v.parent_id AS district_id
    FROM jurisdiction_hierarchy v
    WHERE v.type = 'Village'
),
district_population AS (            -- each village's population once
    SELECT vd.district_id, SUM(vl.total_population) AS district_population
    FROM village_district vd
    JOIN village_locations vl ON vl.village = vd.village
    GROUP BY vd.district_id
),
district_beneficiaries AS (         -- beneficiary totals per district
    SELECT
        vd.district_id,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS total_individual_beneficiaries,
        COUNT(DISTINCT b.partner) AS number_of_partners
    FROM village_district vd
    JOIN beneficiary_partner_data b ON b.village = vd.village
    GROUP BY vd.district_id
)
SELECT
    r.name AS region,
    d.name AS district,
    COALESCE(db.total_individual_beneficiaries, 0) AS total_individual_beneficiaries,
    COALESCE(dp.district_population, 0)           AS district_population,
    ROUND(COALESCE(db.total_individual_beneficiaries, 0) * 100.0
          / NULLIF(dp.district_population, 0), 2)  AS coverage_pct,
    COALESCE(db.number_of_partners, 0)             AS number_of_partners
FROM jurisdiction_hierarchy d
JOIN jurisdiction_hierarchy r        ON r.id = d.parent_id
LEFT JOIN district_population dp     ON dp.district_id = d.id
LEFT JOIN district_beneficiaries db  ON db.district_id = d.id
WHERE d.type = 'District'
ORDER BY region, total_individual_beneficiaries DESC;


-- =====================================================================
-- TASK 5: WINDOW FUNCTIONS
-- A window function calculates across a set of rows but, unlike
-- GROUP BY, keeps every row in the result.
-- =====================================================================

-- 5A. Partner ranking with RANK() - tied partners share a rank.
SELECT
    partner,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END) AS total_individual_beneficiaries,
    RANK() OVER (
        ORDER BY SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                          ELSE beneficiaries END) DESC
    ) AS partner_rank
FROM beneficiary_partner_data
GROUP BY partner
ORDER BY partner_rank;

-- 5B. District ranking within each region (PARTITION BY restarts the
-- ranking for every region).
WITH district_totals AS (
    SELECT
        r.name AS region,
        d.name AS district,
        COALESCE(SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                          ELSE b.beneficiaries END), 0) AS total_individual_beneficiaries
    FROM jurisdiction_hierarchy d
    JOIN jurisdiction_hierarchy r          ON r.id = d.parent_id
    LEFT JOIN jurisdiction_hierarchy v     ON v.parent_id = d.id AND v.type = 'Village'
    LEFT JOIN beneficiary_partner_data b   ON b.village = v.name
    WHERE d.type = 'District'
    GROUP BY r.name, d.name
)
SELECT
    region,
    district,
    total_individual_beneficiaries,
    RANK() OVER (PARTITION BY region
                 ORDER BY total_individual_beneficiaries DESC) AS rank_in_region
FROM district_totals
ORDER BY region, rank_in_region;

-- 5C. Top partner per district with ROW_NUMBER() - always exactly one
-- row per district (partner name breaks any tie).
WITH partner_district AS (
    SELECT
        d.name AS district,
        b.partner,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS individual_beneficiaries
    FROM beneficiary_partner_data b
    JOIN jurisdiction_hierarchy v ON v.name = b.village AND v.type = 'Village'
    JOIN jurisdiction_hierarchy d ON d.id = v.parent_id
    GROUP BY d.name, b.partner
),
numbered AS (
    SELECT
        district,
        partner,
        individual_beneficiaries,
        ROW_NUMBER() OVER (PARTITION BY district
                           ORDER BY individual_beneficiaries DESC, partner) AS rn
    FROM partner_district
)
SELECT district, partner AS top_partner, individual_beneficiaries
FROM numbered
WHERE rn = 1
ORDER BY district;


-- =====================================================================
-- TASK 6: VIEWS
-- A view is a saved query: unlike the Week 1 CREATE TABLE AS tables,
-- it always reflects the current data.
-- Week 1 created TABLES with these same names, so they are dropped
-- first. The DO block drops whichever kind of object exists, so this
-- section can be rerun safely.
-- =====================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'public' AND tablename = 'district_summary') THEN
        DROP TABLE district_summary;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'public' AND tablename = 'partner_summary') THEN
        DROP TABLE partner_summary;
    END IF;
END $$;

DROP VIEW IF EXISTS district_summary CASCADE;
DROP VIEW IF EXISTS partner_summary  CASCADE;

-- 6A. district_summary
CREATE VIEW district_summary AS
WITH village_district AS (
    SELECT v.name AS village, v.parent_id AS district_id
    FROM jurisdiction_hierarchy v
    WHERE v.type = 'Village'
),
district_population AS (
    SELECT vd.district_id, SUM(vl.total_population) AS district_population
    FROM village_district vd
    JOIN village_locations vl ON vl.village = vd.village
    GROUP BY vd.district_id
),
district_beneficiaries AS (
    SELECT
        vd.district_id,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS total_individual_beneficiaries,
        COUNT(DISTINCT b.partner) AS number_of_partners
    FROM village_district vd
    JOIN beneficiary_partner_data b ON b.village = vd.village
    GROUP BY vd.district_id
)
SELECT
    r.name AS region,
    d.name AS district,
    COALESCE(dp.district_population, 0)            AS district_population,
    COALESCE(db.total_individual_beneficiaries, 0) AS total_individual_beneficiaries,
    ROUND(COALESCE(db.total_individual_beneficiaries, 0) * 100.0
          / NULLIF(dp.district_population, 0), 2)  AS coverage_pct,
    COALESCE(db.number_of_partners, 0)             AS number_of_partners
FROM jurisdiction_hierarchy d
JOIN jurisdiction_hierarchy r        ON r.id = d.parent_id
LEFT JOIN district_population dp     ON dp.district_id = d.id
LEFT JOIN district_beneficiaries db  ON db.district_id = d.id
WHERE d.type = 'District';

SELECT * FROM district_summary ORDER BY region, district;

-- 6B. partner_summary
CREATE VIEW partner_summary AS
SELECT
    b.partner,
    SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
             ELSE b.beneficiaries END) AS total_individual_beneficiaries,
    COUNT(DISTINCT b.village)          AS villages_served,
    COUNT(DISTINCT v.parent_id)        AS districts_reached
FROM beneficiary_partner_data b
JOIN jurisdiction_hierarchy v ON v.name = b.village AND v.type = 'Village'
GROUP BY b.partner;

SELECT * FROM partner_summary ORDER BY total_individual_beneficiaries DESC;


-- =====================================================================
-- TASK 7: TRIGGERS
-- In PostgreSQL a trigger has two parts: a trigger FUNCTION (the logic)
-- and the TRIGGER itself (when to run it).
-- =====================================================================

-- 7A. Beneficiary validation: BEFORE INSERT, reject negative values.
CREATE OR REPLACE FUNCTION fn_validate_beneficiaries()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.beneficiaries < 0 THEN
        RAISE EXCEPTION 'Insert rejected: beneficiaries cannot be negative (got %) for partner % in %',
            NEW.beneficiaries, NEW.partner, NEW.village;
    END IF;
    RETURN NEW;   -- returning NEW lets the insert go ahead
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_beneficiaries ON beneficiary_partner_data;
CREATE TRIGGER trg_validate_beneficiaries
BEFORE INSERT ON beneficiary_partner_data
FOR EACH ROW
EXECUTE FUNCTION fn_validate_beneficiaries();

-- 7B. Insert logging: log table + AFTER INSERT trigger.
-- AFTER INSERT is used so only rows that were actually saved get logged.
CREATE TABLE IF NOT EXISTS beneficiary_insert_log (
    log_id            SERIAL PRIMARY KEY,
    partner_id        INTEGER,
    partner           VARCHAR(30),
    village           VARCHAR(30),
    beneficiaries     INTEGER,
    beneficiary_type  VARCHAR(30),
    inserted_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    inserted_by       VARCHAR(50) DEFAULT CURRENT_USER
);

CREATE OR REPLACE FUNCTION fn_log_beneficiary_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO beneficiary_insert_log
        (partner_id, partner, village, beneficiaries, beneficiary_type)
    VALUES
        (NEW.partner_id, NEW.partner, NEW.village, NEW.beneficiaries, NEW.beneficiary_type);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_beneficiary_insert ON beneficiary_partner_data;
CREATE TRIGGER trg_log_beneficiary_insert
AFTER INSERT ON beneficiary_partner_data
FOR EACH ROW
EXECUTE FUNCTION fn_log_beneficiary_insert();

-- ---- Testing the triggers -------------------------------------------
-- Test 1: a negative value is blocked. The DO block catches the error
-- so the rest of the script keeps running; the message appears in
-- DBeaver's Output tab.
DO $$
BEGIN
    INSERT INTO beneficiary_partner_data
        (partner_id, partner, village, beneficiaries, beneficiary_type)
    VALUES (99, 'CARE', 'Xubow', -50, 'Individuals');
    RAISE NOTICE 'Test FAILED: negative value was inserted';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'Test passed - %', SQLERRM;
END $$;

-- Test 2: a valid insert is saved and logged.
INSERT INTO beneficiary_partner_data
    (partner_id, partner, village, beneficiaries, beneficiary_type)
VALUES (99, 'CARE', 'Xubow', 100, 'Individuals');

SELECT * FROM beneficiary_insert_log ORDER BY log_id DESC;

-- Remove the test row so it does not change the analysis results.
-- (The log entry is kept: a log is a history of what happened.)
DELETE FROM beneficiary_partner_data WHERE partner_id = 99;


-- =====================================================================
-- TASK 8: STORED PROCEDURES
-- PostgreSQL's CREATE PROCEDURE cannot return a result set to a SELECT,
-- so report "procedures" that return rows are written as FUNCTIONS
-- with RETURNS TABLE. This is the standard PostgreSQL approach.
-- Both build on the Task 6 views, and name matching ignores case.
-- An unknown name simply returns no rows.
-- =====================================================================

-- 8A. GetPartnerReport(partner_name)
-- The rank is calculated across ALL partners first (inner query) and
-- only then filtered to the requested partner; filtering first would
-- make every partner rank 1.
CREATE OR REPLACE FUNCTION GetPartnerReport(p_partner_name VARCHAR)
RETURNS TABLE (
    partner                        VARCHAR,
    total_individual_beneficiaries BIGINT,
    villages_served                BIGINT,
    districts_reached              BIGINT,
    partner_rank                   BIGINT
)
LANGUAGE sql
AS $$
    SELECT ranked.partner,
           ranked.total_individual_beneficiaries,
           ranked.villages_served,
           ranked.districts_reached,
           ranked.partner_rank
    FROM (
        SELECT ps.*,
               RANK() OVER (ORDER BY ps.total_individual_beneficiaries DESC) AS partner_rank
        FROM partner_summary ps
    ) ranked
    WHERE LOWER(ranked.partner) = LOWER(p_partner_name);
$$;

-- 8B. GetDistrictImpact(district_name)
CREATE OR REPLACE FUNCTION GetDistrictImpact(p_district_name VARCHAR)
RETURNS TABLE (
    region                         VARCHAR,
    district                       VARCHAR,
    district_population            BIGINT,
    total_individual_beneficiaries BIGINT,
    coverage_rate                  NUMERIC,
    number_of_partners             BIGINT
)
LANGUAGE sql
AS $$
    SELECT ds.region,
           ds.district,
           ds.district_population,
           ds.total_individual_beneficiaries,
           ds.coverage_pct,
           ds.number_of_partners
    FROM district_summary ds
    WHERE LOWER(ds.district) = LOWER(p_district_name);
$$;

-- Calling the procedures
SELECT * FROM GetPartnerReport('World Vision');
SELECT * FROM GetPartnerReport('CARE');
SELECT * FROM GetPartnerReport('IRC');

SELECT * FROM GetDistrictImpact('Balcad');
SELECT * FROM GetDistrictImpact('Jowhar');
SELECT * FROM GetDistrictImpact('Beledweyn');


-- =====================================================================
-- ADVANCED CHALLENGES
-- =====================================================================

-- Challenge 1: Partner with the highest number of beneficiaries in
-- each district. Unlike Task 5C, RANK() is used so that if two partners
-- tie for first place, both are shown.
WITH partner_district AS (
    SELECT
        d.name AS district,
        b.partner,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS individual_beneficiaries
    FROM beneficiary_partner_data b
    JOIN jurisdiction_hierarchy v ON v.name = b.village AND v.type = 'Village'
    JOIN jurisdiction_hierarchy d ON d.id = v.parent_id
    GROUP BY d.name, b.partner
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY district ORDER BY individual_beneficiaries DESC) AS rnk
    FROM partner_district
)
SELECT district, partner, individual_beneficiaries
FROM ranked
WHERE rnk = 1
ORDER BY district;

-- Challenge 2: Districts with coverage above the overall average
-- district coverage. AVG ignores NULL, so a district with no population
-- (Beledweyn) does not pull the average down.
SELECT region, district, coverage_pct
FROM district_summary
WHERE coverage_pct > (SELECT AVG(coverage_pct) FROM district_summary)
ORDER BY coverage_pct DESC;

-- Challenge 3: Partners that are the dominant partner in at least one
-- district. "Dominant" = the partner with the largest share of a
-- district's individual beneficiaries. The share is shown too, because
-- the top partner does not always hold a majority.
WITH partner_district AS (
    SELECT
        d.name AS district,
        b.partner,
        SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                 ELSE b.beneficiaries END) AS individual_beneficiaries
    FROM beneficiary_partner_data b
    JOIN jurisdiction_hierarchy v ON v.name = b.village AND v.type = 'Village'
    JOIN jurisdiction_hierarchy d ON d.id = v.parent_id
    GROUP BY d.name, b.partner
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY district ORDER BY individual_beneficiaries DESC) AS rnk,
           ROUND(individual_beneficiaries * 100.0
                 / SUM(individual_beneficiaries) OVER (PARTITION BY district), 2) AS share_pct
    FROM partner_district
)
SELECT
    partner,
    COUNT(*)                                         AS districts_dominated,
    STRING_AGG(district || ' (' || share_pct || '%)', ', ' ORDER BY district) AS dominated_districts
FROM ranked
WHERE rnk = 1
GROUP BY partner
ORDER BY districts_dominated DESC, partner;