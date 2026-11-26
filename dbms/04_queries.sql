
-- ============================================================
-- EventHub - Application Query Patterns
-- CP3: Query Documentation
-- These are equivalent SQL patterns for Prisma operations.
-- ============================================================


-- ============================================================
-- 1. AUTHENTICATION & USER QUERIES
-- ============================================================


-- WRITE: Register a new user
INSERT INTO "User" (
    "id", "name", "email", "passwordHash", "role",
    "createdAt", "updatedAt"
)
VALUES (
    $1, $2, $3, $4, 'ATTENDEE', NOW(), NOW()
)
RETURNING *;


-- READ: Find user for login using email
SELECT *
FROM "User"
WHERE "email" = $1
LIMIT 1;


-- READ: Find refresh token by token hash
SELECT *
FROM "RefreshToken"
WHERE "tokenHash" = $1
LIMIT 1;


-- WRITE: Create refresh token session
INSERT INTO "RefreshToken" (
    "id", "userId", "familyId", "tokenHash",
    "expiresAt", "createdAt"
)
VALUES ($1, $2, $3, $4, $5, NOW())
RETURNING *;


-- READ: Find user by ID during token refresh
SELECT *
FROM "User"
WHERE "id" = $1
LIMIT 1;


-- WRITE: Mark refresh token as used during rotation
UPDATE "RefreshToken"
SET "usedAt" = NOW()
WHERE "id" = $1
  AND "usedAt" IS NULL
  AND "revokedAt" IS NULL;


-- WRITE: Create rotated refresh token
INSERT INTO "RefreshToken" (
    "id", "userId", "familyId", "tokenHash",
    "expiresAt", "createdAt"
)
VALUES ($1, $2, $3, $4, $5, NOW())
RETURNING *;


-- READ: Find refresh token family during logout
SELECT "familyId"
FROM "RefreshToken"
WHERE "tokenHash" = $1
LIMIT 1;


-- WRITE: Revoke active refresh tokens in a token family
UPDATE "RefreshToken"
SET "revokedAt" = NOW()
WHERE "familyId" = $1
  AND "revokedAt" IS NULL;


-- WRITE: Update logged-in user's profile name
UPDATE "User"
SET "name" = $2,
    "updatedAt" = NOW()
WHERE "id" = $1
RETURNING "id", "name", "email", "role";


-- READ: Fetch authenticated user by ID
SELECT "id", "name", "email", "role"
FROM "User"
WHERE "id" = $1
LIMIT 1;

-- ============================================================
-- 2. PUBLIC EVENT QUERIES
-- ============================================================

-- READ: Count upcoming public events for pagination
-- Apply the same optional filters as the list query:
-- date range, title search, category, city, and free/paid filter.
SELECT COUNT(*)
FROM "Event"
WHERE "status" = 'PUBLISHED'
  AND "hiddenAt" IS NULL
  AND "startAt" >= NOW();


-- READ: Fetch public events with organizer details
SELECT
    e."id",
    e."title",
    e."description",
    e."category",
    e."coverKey",
    e."venue",
    e."address",
    e."city",
    e."timezone",
    e."startAt",
    e."endAt",
    e."registrationClosesAt",
    e."capacity",
    e."priceMinor",
    e."currency",
    e."status",
    e."createdAt",
    u."id" AS "organizerId",
    u."name" AS "organizerName"
FROM "Event" e
JOIN "User" u
    ON u."id" = e."organizerId"
WHERE e."status" = 'PUBLISHED'
  AND e."hiddenAt" IS NULL
  AND e."startAt" >= NOW()
  -- Optional filters: date range, title search,
  -- category, city, and free/paid price filter
ORDER BY e."startAt" ASC, e."id" ASC
LIMIT $1 OFFSET $2;


-- READ: Fetch public event details with organizer
SELECT
    e.*,
    u."id" AS "organizerId",
    u."name" AS "organizerName"
FROM "Event" e
JOIN "User" u
    ON u."id" = e."organizerId"
WHERE e."id" = $1
  AND e."hiddenAt" IS NULL
  AND e."status" IN ('PUBLISHED', 'CANCELLED');


-- READ: Count active bookings per event for availability
SELECT
    b."eventId",
    COUNT(*) AS "occupiedSeats"
FROM "Booking" b
WHERE b."eventId" IN ($1, $2, $3)
  AND b."status" IN ('PENDING_PAYMENT', 'CONFIRMED')
GROUP BY b."eventId";


-- ============================================================
-- 3. BOOKING QUERIES
-- =======================================================

-- READ: Find existing active booking for a user and event
SELECT *
FROM "Booking"
WHERE "eventId" = $1
  AND "userId" = $2
  AND "status" IN ('PENDING_PAYMENT', 'CONFIRMED')
LIMIT 1;


-- READ: Lock event row during booking transaction
SELECT "id"
FROM "Event"
WHERE "id" = $1::uuid
FOR UPDATE;


-- READ: Fetch event details for booking validation
SELECT *
FROM "Event"
WHERE "id" = $1;


-- READ: Count active bookings to check event capacity
SELECT COUNT(*) AS "activeBookingCount"
FROM "Booking"
WHERE "eventId" = $1
  AND "status" IN ('PENDING_PAYMENT', 'CONFIRMED');


-- WRITE: Create confirmed free booking
INSERT INTO "Booking" (
    "id", "userId", "eventId", "status",
    "amountMinor", "currency", "eventSnapshot",
    "ticketCode", "createdAt", "updatedAt"
)
VALUES (
    $1, $2, $3, 'CONFIRMED',
    0, $4, $5, $6, NOW(), NOW()
)
RETURNING *;


-- READ: Find expired pending bookings for an event
SELECT "id"
FROM "Booking"
WHERE "eventId" = $1
  AND "status" = 'PENDING_PAYMENT'
  AND "holdExpiresAt" <= $2;


-- WRITE: Expire open payments for stale bookings
UPDATE "Payment"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "bookingId" IN ($1, $2, $3)
  AND "status" = 'OPEN';


-- WRITE: Expire stale pending bookings
UPDATE "Booking"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "id" IN ($1, $2, $3)
  AND "status" = 'PENDING_PAYMENT';


-- READ: Find confirmed or unexpired pending paid booking
SELECT b.*, p.*
FROM "Booking" b
LEFT JOIN "Payment" p
    ON p."bookingId" = b."id"
WHERE b."eventId" = $1
  AND b."userId" = $2
  AND (
      b."status" = 'CONFIRMED'
      OR (
          b."status" = 'PENDING_PAYMENT'
          AND b."holdExpiresAt" > $3
      )
  )
LIMIT 1;


-- READ: Count confirmed and non-expired pending bookings
SELECT COUNT(*) AS "activeBookingCount"
FROM "Booking"
WHERE "eventId" = $1
  AND (
      "status" = 'CONFIRMED'
      OR (
          "status" = 'PENDING_PAYMENT'
          AND "holdExpiresAt" > $2
      )
  );


-- WRITE: Create pending paid booking
INSERT INTO "Booking" (
    "id", "userId", "eventId", "status",
    "amountMinor", "currency", "eventSnapshot",
    "holdExpiresAt", "createdAt", "updatedAt"
)
VALUES (
    $1, $2, $3, 'PENDING_PAYMENT',
    $4, $5, $6, $7, NOW(), NOW()
)
RETURNING *;


-- WRITE: Create open payment for booking
INSERT INTO "Payment" (
    "id", "bookingId", "provider", "status",
    "amountMinor", "currency", "createdAt", "updatedAt"
)
VALUES (
    $1, $2, 'razorpay', 'OPEN',
    $3, $4, NOW(), NOW()
)
RETURNING *;


-- READ: Count user's bookings for pagination
SELECT COUNT(*)
FROM "Booking"
WHERE "userId" = $1;


-- READ: List user bookings with event details
SELECT
    b.*,
    e."id" AS "eventId",
    e."title",
    e."startAt",
    e."endAt",
    e."venue",
    e."city",
    e."timezone",
    e."status" AS "eventStatus"
FROM "Booking" b
JOIN "Event" e
    ON e."id" = b."eventId"
WHERE b."userId" = $1
ORDER BY b."createdAt" DESC, b."id" DESC
LIMIT $2 OFFSET $3;


-- READ: Fetch one user's booking with event details
SELECT
    b.*,
    e."id" AS "eventId",
    e."title",
    e."startAt",
    e."endAt",
    e."venue",
    e."city",
    e."timezone",
    e."status" AS "eventStatus"
FROM "Booking" b
JOIN "Event" e
    ON e."id" = b."eventId"
WHERE b."id" = $1
  AND b."userId" = $2
LIMIT 1;


-- READ: Fetch confirmed booking ticket and attendee details
SELECT
    b."id",
    b."status",
    b."ticketCode",
    b."eventSnapshot",
    u."name" AS "attendeeName"
FROM "Booking" b
JOIN "User" u
    ON u."id" = b."userId"
WHERE b."id" = $1
  AND b."userId" = $2
LIMIT 1;


-- READ: Find event associated with user's booking before cancellation
SELECT "eventId"
FROM "Booking"
WHERE "id" = $1
  AND "userId" = $2
LIMIT 1;


-- READ: Fetch booking details before cancellation
SELECT
    "id",
    "eventId",
    "status",
    "amountMinor",
    "checkedInAt",
    "cancelledAt"
FROM "Booking"
WHERE "id" = $1
  AND "userId" = $2
LIMIT 1;


-- READ: Fetch event start time to validate cancellation
SELECT "startAt"
FROM "Event"
WHERE "id" = $1;


-- WRITE: Cancel confirmed free booking
UPDATE "Booking"
SET "status" = 'CANCELLED',
    "cancelledAt" = NOW(),
    "ticketCode" = NULL,
    "updatedAt" = NOW()
WHERE "id" = $1
  AND "userId" = $2;


-- ============================================================
-- 4. PAYMENT & WEBHOOK QUERIES
-- ============================================================

-- READ: Find booking owned by user
SELECT "id", "eventId"
FROM "Booking"
WHERE "id" = $1 AND "userId" = $2
LIMIT 1;

-- READ: Lock event during checkout transaction
SELECT "id"
FROM "Event"
WHERE "id" = $1::uuid
FOR UPDATE;

-- READ: Lock booking during checkout transaction
SELECT "id"
FROM "Booking"
WHERE "id" = $1::uuid
FOR UPDATE;

-- READ: Lock payment during checkout transaction
SELECT "id"
FROM "Payment"
WHERE "id" = $1::uuid
FOR UPDATE;

-- READ: Fetch booking with associated payment
SELECT
    b."id",
    b."eventId",
    b."status",
    b."holdExpiresAt",
    b."amountMinor",
    b."currency",
    p."id" AS "paymentId",
    p."provider",
    p."providerCheckoutId",
    p."providerPaymentId",
    p."status" AS "paymentStatus",
    p."amountMinor" AS "paymentAmountMinor",
    p."currency" AS "paymentCurrency"
FROM "Booking" b
LEFT JOIN "Payment" p
    ON p."bookingId" = b."id"
WHERE b."id" = $1
  AND b."userId" = $2
LIMIT 1;

-- WRITE: Expire open payment
UPDATE "Payment"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "id" = $1
  AND "status" = 'OPEN';

-- WRITE: Expire pending booking
UPDATE "Booking"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "id" = $1
  AND "status" = 'PENDING_PAYMENT';

-- WRITE: Save checkout session ID to payment
UPDATE "Payment"
SET "providerCheckoutId" = $2,
    "updatedAt" = NOW()
WHERE "id" = $1;

-- READ: Find payment by checkout session and booking owner
SELECT p."bookingId"
FROM "Payment" p
JOIN "Booking" b
    ON b."id" = p."bookingId"
WHERE p."provider" = 'razorpay'
  AND p."providerCheckoutId" = $1
  AND b."userId" = $2
LIMIT 1;

-- READ: Find payment using dynamic payment lookup criteria
-- The lookup condition is selected based on the payment identifier
-- provided (for example, payment ID, checkout ID, or provider payment ID).
SELECT
    p."id",
    p."bookingId",
    b."eventId"
FROM "Payment" p
JOIN "Booking" b
    ON b."id" = p."bookingId"
WHERE /* dynamically selected payment lookup condition */
LIMIT 1;

-- WRITE: Record webhook event to prevent duplicate processing
INSERT INTO "ProcessedWebhook" (
    "provider",
    "providerEventId"
)
VALUES ('razorpay', $1)
ON CONFLICT ("provider", "providerEventId") DO NOTHING;

-- READ: Fetch payment and associated booking state
SELECT
    p.*,
    b."id" AS "bookingId",
    b."eventId",
    b."status" AS "bookingStatus",
    b."holdExpiresAt",
    b."ticketCode"
FROM "Payment" p
JOIN "Booking" b
    ON b."id" = p."bookingId"
WHERE p."id" = $1
LIMIT 1;

-- WRITE: Mark late payment as requiring refund
UPDATE "Payment"
SET "status" = 'REFUND_REQUIRED',
    "providerPaymentId" = $2,
    "updatedAt" = NOW()
WHERE "id" = $1;

-- WRITE: Mark booking as requiring refund
UPDATE "Booking"
SET "status" = 'REFUND_REQUIRED',
    "updatedAt" = NOW()
WHERE "id" = $1;

-- WRITE: Mark payment as paid
UPDATE "Payment"
SET "status" = 'PAID',
    "providerPaymentId" = $2,
    "updatedAt" = NOW()
WHERE "id" = $1;

-- WRITE: Confirm booking and generate ticket
UPDATE "Booking"
SET "status" = 'CONFIRMED',
    "ticketCode" = $2,
    "holdExpiresAt" = NULL,
    "updatedAt" = NOW()
WHERE "id" = $1;

-- WRITE: Expire failed open payment
UPDATE "Payment"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "id" = $1;

-- WRITE: Expire booking after payment failure
UPDATE "Booking"
SET "status" = 'EXPIRED',
    "updatedAt" = NOW()
WHERE "id" = $1;


-- ============================================================
-- 5. ORGANIZER EVENT QUERIES
-- ============================================================

-- READ: Find event owned by organizer
SELECT *
FROM "Event"
WHERE "id" = $1
  AND "organizerId" = $2
LIMIT 1;

-- READ: Check whether event has any bookings
SELECT COUNT(*) AS "bookingCount"
FROM "Booking"
WHERE "eventId" = $1;

-- READ: Count active bookings for organizer events
-- Event ID placeholders vary based on the number of events.
SELECT "eventId", COUNT(*) AS "bookingCount"
FROM "Booking"
WHERE "eventId" IN ($1, $2, $3)
  AND "status" IN ('PENDING_PAYMENT', 'CONFIRMED')
GROUP BY "eventId";

-- READ: Count checked-in attendees for organizer events
SELECT "eventId", COUNT(*) AS "checkedInCount"
FROM "Booking"
WHERE "eventId" IN ($1, $2, $3)
  AND "status" = 'CONFIRMED'
  AND "checkedInAt" IS NOT NULL
GROUP BY "eventId";

-- WRITE: Create organizer draft event
INSERT INTO "Event" (
    "id", "organizerId", "title", "description", "category",
    "coverKey", "venue", "address", "city", "timezone",
    "startAt", "endAt", "registrationClosesAt",
    "capacity", "priceMinor", "currency", "status",
    "createdAt", "updatedAt"
)
VALUES (
    $1, $2, $3, $4, $5,
    $6, $7, $8, $9, $10,
    $11, $12, $13,
    $14, $15, $16, 'DRAFT',
    NOW(), NOW()
)
RETURNING *;

-- WRITE: Partially update organizer-owned event
-- Only fields supplied by the organizer are updated.
-- The SET clause is dynamically constructed by the application.
UPDATE "Event"
SET /* dynamically supplied fields */,
    "updatedAt" = NOW()
WHERE "id" = $1
  AND "organizerId" = $2
RETURNING *;

-- WRITE: Publish organizer event
UPDATE "Event"
SET "status" = 'PUBLISHED',
    "updatedAt" = NOW()
WHERE "id" = $1
RETURNING *;

-- READ: Count organizer's events for pagination
SELECT COUNT(*)
FROM "Event"
WHERE "organizerId" = $1;

-- READ: Fetch organizer's events with pagination
SELECT *
FROM "Event"
WHERE "organizerId" = $1
ORDER BY "createdAt" DESC, "id" DESC
LIMIT $2 OFFSET $3;

-- WRITE: Delete organizer-owned draft event
DELETE FROM "Event"
WHERE "id" = $1
  AND "organizerId" = $2
RETURNING "id";

-- WRITE: Cancel active bookings for organizer event
UPDATE "Booking"
SET "status" = 'CANCELLED',
    "cancelledAt" = NOW(),
    "ticketCode" = NULL,
    "updatedAt" = NOW()
WHERE "eventId" = $1
  AND "status" IN ('PENDING_PAYMENT', 'CONFIRMED');

-- WRITE: Mark organizer event as cancelled
UPDATE "Event"
SET "status" = 'CANCELLED',
    "cancelledAt" = NOW(),
    "updatedAt" = NOW()
WHERE "id" = $1
RETURNING *;

-- READ: Count confirmed attendees (optional name search)
SELECT COUNT(*)
FROM "Booking" b
WHERE b."eventId" = $1
  AND b."status" = 'CONFIRMED'
  AND (
      $2 IS NULL
      OR EXISTS (
          SELECT 1
          FROM "User" u
          WHERE u."id" = b."userId"
            AND u."name" ILIKE '%' || $2 || '%'
      )
  );

-- READ: Fetch confirmed attendees with name and check-in status
SELECT
    b."id" AS "bookingId",
    b."checkedInAt",
    u."name"
FROM "Booking" b
JOIN "User" u
    ON u."id" = b."userId"
WHERE b."eventId" = $1
  AND b."status" = 'CONFIRMED'
  AND ($2 IS NULL OR u."name" ILIKE '%' || $2 || '%')
ORDER BY b."createdAt" DESC, b."id" DESC
LIMIT $3 OFFSET $4;

-- READ: Lock event during ticket check-in
SELECT "id"
FROM "Event"
WHERE "id" = $1::uuid
FOR UPDATE;

-- READ: Verify event ownership and fetch check-in details
SELECT "id", "startAt", "endAt", "status", "hiddenAt"
FROM "Event"
WHERE "id" = $1
  AND "organizerId" = $2
LIMIT 1;

-- READ: Lock booking row matching ticket and event
SELECT "id"
FROM "Booking"
WHERE "ticketCode" = $1
  AND "eventId" = $2::uuid
FOR UPDATE;

-- READ: Verify ticket status and check-in state
SELECT "id", "status", "checkedInAt"
FROM "Booking"
WHERE "ticketCode" = $1
  AND "eventId" = $2
LIMIT 1;

-- WRITE: Mark confirmed ticket as checked in
UPDATE "Booking"
SET "checkedInAt" = $2,
    "updatedAt" = NOW()
WHERE "id" = $1;
