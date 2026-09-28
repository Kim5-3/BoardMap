
-- BOARDMAP - IT108 ACTIVITY 5
-- Database Views, Functions, Procedures, and Triggers

-- Connect to: boardmap_db
-- Schema: system_core



-- SECTION 0 - CONNECTION CHECK
SELECT current_database();



-- SECTION 1 - VIEWS

-- V01 - APPROVED BOARDING HOUSES
-- BoardMap feature: student/seeker map and search.
-- only approved listings are exposed, with owner and location data.

CREATE OR REPLACE VIEW system_core.vw_approved_boarding_houses AS
SELECT
    bh.boarding_house_id,
    bh.house_name,
    bh.description,
    bh.capacity,
    bh.contact_number,
    bho.name AS owner_name,
    bho.contact_number AS owner_contact,
    l.barangay_name,
    l.city,
    l.province,
    l.latitude,
    l.longitude
FROM system_core.boarding_houses AS bh
INNER JOIN system_core.boarding_house_owners AS bho
    ON bh.owner_id = bho.owner_id
INNER JOIN system_core.locations AS l
    ON bh.location_id = l.location_id
WHERE bh.status = 'approved';


-- V02 - AVAILABLE BOARDING ROOMS
-- BoardMap feature: student/seeker room availability search.
-- only approved houses with available rooms and slots > 0.

CREATE OR REPLACE VIEW system_core.vw_available_boarding_rooms AS
SELECT
    bh.boarding_house_id,
    bh.house_name,
    r.room_id,
    r.room_type,
    r.price,
    r.capacity,
    r.available_slots,
    l.barangay_name,
    l.city,
    l.province,
    l.latitude,
    l.longitude
FROM system_core.boarding_houses AS bh
INNER JOIN system_core.rooms AS r
    ON r.boarding_house_id = bh.boarding_house_id
INNER JOIN system_core.locations AS l
    ON l.location_id = bh.location_id
WHERE bh.status = 'approved'
  AND r.status = 'available'
  AND r.available_slots > 0;



-- SECTION 2 - FUNCTIONS

-- F01 - AVAILABLE ROOM SLOT COUNT
-- BoardMap feature: listing availability/search support.
-- Returns total available slots for one boarding house.

CREATE OR REPLACE FUNCTION system_core.fn_get_available_room_count(
    p_boarding_house_id BIGINT
)
RETURNS INTEGER
LANGUAGE plpgsql
AS 'BEGIN
    RETURN (
        SELECT COALESCE(SUM(r.available_slots), 0)::INTEGER
        FROM system_core.rooms AS r
        WHERE r.boarding_house_id = p_boarding_house_id
          AND r.status = ''available''
          AND r.available_slots > 0
    );
END;';


-- F02 - BOARDING HOUSE AVAILABILITY
-- BoardMap feature: search/filter availability.
-- TRUE when an existing house has at least one available room slot.
-- Raises a controlled exception when the house ID does not exist.

CREATE OR REPLACE FUNCTION system_core.fn_is_boarding_house_available(
    p_boarding_house_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS 'BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM system_core.boarding_houses AS bh
        WHERE bh.boarding_house_id = p_boarding_house_id
    ) THEN
        RAISE EXCEPTION ''Boarding house ID % does not exist.'',
            p_boarding_house_id;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM system_core.rooms AS r
        WHERE r.boarding_house_id = p_boarding_house_id
          AND r.status = ''available''
          AND r.available_slots > 0
    );
END;';



-- SECTION 3 - STORED PROCEDURE

-- P01 - DEACTIVATE BOARDING HOUSE
-- BoardMap feature: owner listing management.
-- Rule: supplied owner must own the specified boarding house.
-- Effect: house and all its rooms become inactive.
-- WARNING:this changes data; use a development DB or transaction.

CREATE OR REPLACE PROCEDURE system_core.sp_deactivate_boarding_house(
    p_boarding_house_id BIGINT,
    p_owner_id BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM system_core.boarding_houses
        WHERE boarding_house_id = p_boarding_house_id
          AND owner_id = p_owner_id
    ) THEN
        RAISE EXCEPTION
            'Boarding house % was not found or does not belong to owner %',
            p_boarding_house_id,
            p_owner_id;
    END IF;

    UPDATE system_core.boarding_houses
    SET status = 'inactive'
    WHERE boarding_house_id = p_boarding_house_id;

    UPDATE system_core.rooms
    SET status = 'inactive'
    WHERE boarding_house_id = p_boarding_house_id;
END;
$$;



-- SECTION 4 - TRIGGER FUNCTIONS AND TRIGGERS

-- T01 - ROOM STATUS FROM AVAILABLE SLOTS
-- Rule: 0 slots -> full; slots > 0 and currently full -> available.

CREATE OR REPLACE FUNCTION system_core.tg_room_status_from_slots()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.available_slots = 0 THEN
        NEW.status := 'full';
    ELSIF NEW.available_slots > 0 AND NEW.status = 'full' THEN
        NEW.status := 'available';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_room_status_from_slots
ON system_core.rooms;

CREATE TRIGGER trg_room_status_from_slots
BEFORE INSERT OR UPDATE OF available_slots, status
ON system_core.rooms
FOR EACH ROW
EXECUTE FUNCTION system_core.tg_room_status_from_slots();


-- T02 - REAPPROVAL WHEN APPROVED LISTING CHANGES
-- Rule: changes to important approved-listing fields require re-review.

CREATE OR REPLACE FUNCTION system_core.tg_reapproval_on_listing_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status = 'approved' AND (
        NEW.owner_id IS DISTINCT FROM OLD.owner_id OR
        NEW.location_id IS DISTINCT FROM OLD.location_id OR
        NEW.house_name IS DISTINCT FROM OLD.house_name OR
        NEW.description IS DISTINCT FROM OLD.description OR
        NEW.capacity IS DISTINCT FROM OLD.capacity OR
        NEW.contact_number IS DISTINCT FROM OLD.contact_number
    ) THEN
        NEW.status := 'pending';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reapproval_on_listing_change
ON system_core.boarding_houses;

CREATE TRIGGER trg_reapproval_on_listing_change
BEFORE UPDATE OF owner_id, location_id, house_name,
description, capacity, contact_number
ON system_core.boarding_houses
FOR EACH ROW
EXECUTE FUNCTION system_core.tg_reapproval_on_listing_change();



-- SECTION 5 - OBJECT VERIFICATION


-- Verify the two views.
SELECT table_schema, table_name
FROM information_schema.views
WHERE table_schema = 'system_core'
  AND table_name IN (
      'vw_approved_boarding_houses',
      'vw_available_boarding_rooms'
  )
ORDER BY table_name;

-- Verify functions/procedure.
SELECT routine_schema, routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'system_core'
  AND routine_name IN (
      'fn_get_available_room_count',
      'fn_is_boarding_house_available',
      'sp_deactivate_boarding_house',
      'tg_room_status_from_slots',
      'tg_reapproval_on_listing_change'
  )
ORDER BY routine_name;

-- Verify triggers.
SELECT
    trigger_schema,
    trigger_name,
    event_object_table,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'system_core'
  AND trigger_name IN (
      'trg_room_status_from_slots',
      'trg_reapproval_on_listing_change'
  )
ORDER BY trigger_name;



-- SECTION 6 - REQUIRED TESTING / SCREENSHOT EVIDENCE


-- TEST 1 - V01 APPROVED BOARDING HOUSES VIEW
-- Expected: approved houses with owner/location fields.


SELECT *
FROM system_core.vw_approved_boarding_houses;


-- TEST 2 - V02 AVAILABLE BOARDING ROOMS VIEW
-- Expected: approved houses, available rooms, slots > 0.


SELECT *
FROM system_core.vw_available_boarding_rooms;


-- TEST 3 - F01 AVAILABLE ROOM COUNT
-- Input: boarding_house_id = 1.
-- Expected: integer count of available slots.

SELECT system_core.fn_get_available_room_count(1);


-- TEST 4 - F02 BOARDING HOUSE AVAILABILITY
-- Input: boarding_house_id = 1.
-- Expected: TRUE/FALSE according to actual room availability.

SELECT system_core.fn_is_boarding_house_available(1);


-- TEST 5 - F02 INVALID ID / CONTROLLED EXCEPTION
-- Input: non-existing ID.
-- Expected: controlled "does not exist" exception.


SELECT system_core.fn_is_boarding_house_available(99999);


-- TEST 6 - P01 PROCEDURE BEFORE/AFTER
-- Expected: house and related rooms become inactive.
-- Use transaction so the test can be rolled back.
-- Confirm owner_id=1 really owns house 1 before testing.


BEGIN;

-- BEFORE
SELECT
    boarding_house_id,
    house_name,
    owner_id,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;

SELECT
    room_id,
    boarding_house_id,
    room_type,
    price,
    available_slots,
    status
FROM system_core.rooms
WHERE boarding_house_id = 1;

-- PROCEDURE
CALL system_core.sp_deactivate_boarding_house(1, 1);

-- AFTER
SELECT
    boarding_house_id,
    house_name,
    owner_id,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;

SELECT
    room_id,
    boarding_house_id,
    room_type,
    price,
    available_slots,
    status
FROM system_core.rooms
WHERE boarding_house_id = 1;

ROLLBACK;


-- TEST 7 - P01 WRONG OWNER / EXCEPTION
-- Expected: controlled exception and no unintended data change.


SELECT
    boarding_house_id,
    house_name,
    owner_id,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;

CALL system_core.sp_deactivate_boarding_house(1, 999999);

SELECT
    boarding_house_id,
    house_name,
    owner_id,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;


-- TEST 8 - T01 ROOM STATUS TRIGGER
-- Expected: available_slots=0 automatically results in status='full'.
-- Use transaction so the test can be rolled back.

BEGIN;

SELECT
    room_id,
    boarding_house_id,
    room_type,
    available_slots,
    status
FROM system_core.rooms
WHERE room_id = 1;

UPDATE system_core.rooms
SET available_slots = 0
WHERE room_id = 1;

SELECT
    room_id,
    boarding_house_id,
    room_type,
    available_slots,
    status
FROM system_core.rooms
WHERE room_id = 1;

ROLLBACK;


-- TEST 9 - T02 LISTING REAPPROVAL TRIGGER
-- Expected: changing an important field on an approved listing
-- changes status to 'pending'.
-- Use transaction so the test can be rolled back.

BEGIN;

SELECT
    boarding_house_id,
    house_name,
    description,
    capacity,
    contact_number,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;

UPDATE system_core.boarding_houses
SET description = 'Updated description for re-review'
WHERE boarding_house_id = 1
  AND status = 'approved';

SELECT
    boarding_house_id,
    house_name,
    description,
    status
FROM system_core.boarding_houses
WHERE boarding_house_id = 1;

ROLLBACK;


-- TEST 10 - REVIEW CONSTRAINT / INVALID RATING
-- Expected: PostgreSQL rejects rating 6 because it is outside
-- the valid rating range defined by the reviews table.
-- Screenshot: Evidence_Test10.png

-- This is intentionally an error test. Capture the PostgreSQL
-- error message as evidence.
-- Do not replace it with a successful INSERT.

INSERT INTO system_core.reviews
    (user_id, boarding_house_id, rating, comment)
VALUES
    (2, 2, 6, 'Invalid rating test');



-- OPTIONAL SUPPORTING QUERIES
-- These are useful for documentation but do NOT replace the
-- required 10 tests.


-- Approved listing status overview
SELECT
    boarding_house_id,
    house_name,
    status,
    date_registered
FROM system_core.boarding_houses
ORDER BY date_registered DESC, house_name ASC;

-- Available room price/slot summary
SELECT
    COUNT(*) AS room_count,
    MIN(price) AS minimum_room_price,
    MAX(price) AS maximum_room_price,
    ROUND(AVG(price), 2) AS average_room_price,
    SUM(available_slots) AS total_available_slots
FROM system_core.rooms
WHERE status = 'available';

-- Approved listings by owner
SELECT
    bho.owner_id,
    bho.name AS owner_name,
    COUNT(bh.boarding_house_id) AS approved_listing_count
FROM system_core.boarding_house_owners AS bho
INNER JOIN system_core.boarding_houses AS bh
    ON bh.owner_id = bho.owner_id
WHERE bh.status = 'approved'
GROUP BY bho.owner_id, bho.name
HAVING COUNT(bh.boarding_house_id) >= 1
ORDER BY approved_listing_count DESC, owner_name;

-- Approved houses with room and map details
SELECT
    bh.boarding_house_id,
    bh.house_name,
    l.barangay_name,
    l.latitude,
    l.longitude,
    r.room_id,
    r.room_type,
    r.price,
    r.available_slots,
    r.status AS room_status
FROM system_core.boarding_houses AS bh
INNER JOIN system_core.locations AS l
    ON bh.location_id = l.location_id
INNER JOIN system_core.rooms AS r
    ON bh.boarding_house_id = r.boarding_house_id
WHERE bh.status = 'approved'
ORDER BY bh.house_name, r.price;


