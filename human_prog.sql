-- =====================================================================
-- HUMANITARIAN PROGRAMME DATA ANALYSIS
-- PostgreSQL (Docker) + DBeaver
-- =====================================================================


-- =====================================================================
-- 0. DATABASE CREATION
-- Run this ONE line on its own while connected to the default
-- "postgres" database. Then point your DBeaver connection at
-- humanitarian_program and run the rest of the file.
-- =====================================================================
CREATE DATABASE humanitarian_program;


-- =====================================================================
-- 1. TABLE CREATION
-- village_locations is created first because beneficiary_partner_data
-- references it (a foreign key needs its parent table to exist).
-- =====================================================================
DROP TABLE IF EXISTS beneficiary_partner_data;
DROP TABLE IF EXISTS village_locations;
DROP TABLE IF EXISTS jurisdiction_hierarchy;
DROP TABLE IF EXISTS partner_summary;
DROP TABLE IF EXISTS district_summary;

CREATE TABLE village_locations (
    village_id        INTEGER PRIMARY KEY,
    village           VARCHAR(30) UNIQUE,
    latitude          VARCHAR(30),
    longitude         VARCHAR(30),
    total_population  INTEGER
);

CREATE TABLE beneficiary_partner_data (
    partner_id        INTEGER PRIMARY KEY,
    partner           VARCHAR(30),
    village           VARCHAR(30) REFERENCES village_locations(village),
    beneficiaries     INTEGER,
    beneficiary_type  VARCHAR(30)
);

CREATE TABLE jurisdiction_hierarchy (
    id         INTEGER PRIMARY KEY,
    name       VARCHAR(50),
    type       VARCHAR(20),
    parent_id  INTEGER REFERENCES jurisdiction_hierarchy(id)   -- self-reference
);


-- =====================================================================
-- 2. SAMPLE DATA INSERTION
-- =====================================================================
INSERT INTO village_locations
(village_id, village, latitude, longitude, total_population)
VALUES
(1,  'Dharkenley',  '2.0469', '45.3182', 5000),
(2,  'Bulo-Kahin',  '2.0560', '45.3250', 4200),
(3,  'Hilo Kelyo',  '2.0650', '45.3300', 3800),
(4,  'Xubow',       '2.1000', '45.3500', 6000),
(5,  'Xiintooy',    '2.1100', '45.3600', 4500),
(6,  'Dhagax Jebis','2.1200', '45.3700', 5200),
(7,  'Filtare',     '2.1300', '45.3800', 3900),
(8,  'Howl-Wadaag', '2.1400', '45.3900', 4700),
(9,  'Balcad',      '2.1500', '45.4000', 5500),
(10, 'Mareeray',    '2.1600', '45.4100', 4300),
(11, 'Kulmis',      '2.1700', '45.4200', 6058),
(12, 'Sabuun',      '2.1800', '45.4300', 5100),
(13, 'Bayaxaw',     '2.1900', '45.4400', 3600),
(14, 'Bayaxawo',    '2.2000', '45.4500', 4000);

INSERT INTO beneficiary_partner_data
(partner_id, partner, village, beneficiaries, beneficiary_type)
VALUES
(1,  'World Vision', 'Dharkenley',   1200, 'Individuals'),
(2,  'World Vision', 'Bulo-Kahin',    350, 'Households'),
(3,  'CARE',         'Dharkenley',    800, 'Individuals'),
(4,  'CARE',         'Hilo Kelyo',    250, 'Households'),
(5,  'IRC',          'Xubow',        1500, 'Individuals'),
(6,  'IRC',          'Xiintooy',      300, 'Households'),
(7,  'World Vision', 'Dhagax Jebis',  900, 'Individuals'),
(8,  'CARE',         'Filtare',       450, 'Households'),
(9,  'IRC',          'Howl-Wadaag',  1100, 'Individuals'),
(10, 'World Vision', 'Balcad',        700, 'Households'),
(11, 'CARE',         'Mareeray',      600, 'Individuals'),
(12, 'IRC',          'Kulmis',        400, 'Households'),
(13, 'World Vision', 'Sabuun',       1000, 'Individuals'),
(14, 'CARE',         'Bayaxaw',       500, 'Households'),
(15, 'IRC',          'Bayaxawo',     1300, 'Individuals'),
(16, 'World Vision', 'Dharkenley',    700, 'Households'),
(17, 'CARE',         'Bulo-Kahin',    550, 'Individuals'),
(18, 'IRC',          'Hilo Kelyo',    900, 'Individuals');

INSERT INTO jurisdiction_hierarchy
(id, name, type, parent_id)
VALUES
(1,  'Middle Shabelle', 'Region',   NULL),
(2,  'Hiraan',          'Region',   NULL),
(3,  'Balcad',          'District', 1),
(4,  'Jowhar',          'District', 1),
(5,  'Beledweyn',       'District', 2),
(6,  'Dharkenley',      'Village',  3),
(7,  'Bulo-Kahin',      'Village',  3),
(8,  'Hilo Kelyo',      'Village',  3),
(9,  'Xubow',           'Village',  4),
(10, 'Xiintooy',        'Village',  4),
(11, 'Dhagax Jebis',    'Village',  4),
(12, 'Filtare',         'Village',  4),
(13, 'Howl-Wadaag',     'Village',  4),
(14, 'Balcad',          'Village',  4),
(15, 'Mareeray',        'Village',  4),
(16, 'Kulmis',          'Village',  4),
(17, 'Sabuun',          'Village',  4),
(18, 'Bayaxaw',         'Village',  4),
(19, 'Bayaxawo',        'Village',  4);


-- =====================================================================
-- TASK 1: EXPLORE THE DATA
-- =====================================================================

-- 1.1 Display all records from each table
SELECT * FROM beneficiary_partner_data;
SELECT * FROM village_locations;
SELECT * FROM jurisdiction_hierarchy;

-- 1.2 Display the partner, village and beneficiaries
SELECT partner, village, beneficiaries
FROM beneficiary_partner_data;

-- 1.3 Villages with a population greater than 4,500
SELECT village, total_population
FROM village_locations
WHERE total_population > 4500;

-- 1.4 Records where the beneficiary type is Households
SELECT *
FROM beneficiary_partner_data
WHERE beneficiary_type = 'Households';

==================================================================
-- TASK 2: CONVERT BENEFICIARY COUNTS
-- Households are estimated at 6 individuals each.
-- =====================================================================
SELECT
    partner,
    village,
    beneficiaries,
    beneficiary_type,
    CASE
        WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
        ELSE beneficiaries
    END AS individual_beneficiaries
FROM beneficiary_partner_data;


-- =====================================================================
-- TASK 3: PARTNER ANALYSIS
-- =====================================================================
SELECT
    partner,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END)                          AS total_individual_beneficiaries,
    COUNT(DISTINCT village)                                   AS villages_served,
    ROUND(AVG(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                   ELSE beneficiaries END), 2)                AS avg_beneficiaries_per_record
FROM beneficiary_partner_data
GROUP BY partner
ORDER BY total_individual_beneficiaries DESC;


-- =====================================================================
-- TASK 4: VILLAGE COVERAGE
-- 100.0 (not 100) forces decimal maths; otherwise integer division
-- would round most coverage values down to 0.
-- =====================================================================
SELECT
    b.partner,
    b.village,
    CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
         ELSE b.beneficiaries END                             AS individual_beneficiaries,
    v.total_population                                        AS village_population,
    ROUND(
        CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
             ELSE b.beneficiaries END * 100.0 / v.total_population
    , 2)                                                      AS coverage_pct
FROM beneficiary_partner_data b
JOIN village_locations v
    ON b.village = v.village
ORDER BY coverage_pct DESC;


-- =====================================================================
-- TASK 5: ADD DISTRICT INFORMATION
-- Self-join: village row (child) -> its parent row (district).
-- Note: "Balcad" is BOTH a district and a village, so we filter
-- type = 'Village' to avoid matching the district row by mistake.
-- =====================================================================
SELECT
    b.partner,
    b.village,
    d.name AS district,
    CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
         ELSE b.beneficiaries END AS individual_beneficiaries
FROM beneficiary_partner_data b
JOIN jurisdiction_hierarchy vil
    ON vil.name = b.village
   AND vil.type = 'Village'
JOIN jurisdiction_hierarchy d
    ON d.id = vil.parent_id
ORDER BY district, b.village;


-- =====================================================================
-- TASK 6: MULTIPLE-PARTNER VILLAGES
-- =====================================================================
SELECT
    village,
    COUNT(DISTINCT partner) AS number_of_partners 
FROM beneficiary_partner_data
GROUP BY village
HAVING COUNT(DISTINCT partner) > 1
ORDER BY number_of_partners DESC, village;


-- =====================================================================
-- TASK 7: CREATE SUMMARY TABLES (CREATE TABLE AS SELECT)
-- PostgreSQL folds unquoted names to lowercase, so Partner_summary
-- is stored as partner_summary.
-- =====================================================================

-- 7.1 Partner_summary
CREATE TABLE Partner_summary AS
SELECT
    partner,
    SUM(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
             ELSE beneficiaries END)                     AS total_beneficiaries,
    COUNT(DISTINCT village)                              AS villages_served,
    ROUND(AVG(CASE WHEN beneficiary_type = 'Households' THEN beneficiaries * 6
                   ELSE beneficiaries END), 2)           AS average_beneficiaries
FROM beneficiary_partner_data
GROUP BY partner
ORDER BY total_beneficiaries DESC;

SELECT * FROM Partner_summary;

-- 7.2 District_summary
CREATE TABLE District_summary AS
SELECT
    d.name                                                AS district,
    COALESCE(SUM(CASE WHEN b.beneficiary_type = 'Households' THEN b.beneficiaries * 6
                      ELSE b.beneficiaries END), 0)       AS total_individual_beneficiaries,
    COUNT(DISTINCT b.village)                             AS villages_served
FROM jurisdiction_hierarchy d
LEFT JOIN jurisdiction_hierarchy vil
    ON vil.parent_id = d.id
   AND vil.type = 'Village'
LEFT JOIN beneficiary_partner_data b
    ON b.village = vil.name
WHERE d.type = 'District'
GROUP BY d.name;
 
SELECT * FROM District_summary
ORDER BY total_individual_beneficiaries DESC;