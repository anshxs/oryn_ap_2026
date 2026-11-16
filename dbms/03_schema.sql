-- ============================================================================
-- Application Name: Oryn (Social Media Engine)
-- Course: Advanced Programming (AP) / Database Management Systems (DBMS)
-- Year / Cohort: B.Tech 2nd Year (2026)
-- Team No.: T0005 · Section: D
-- Target RDBMS: PostgreSQL 15+
-- Deliverable: dbms/03_schema.sql (Checkpoint 2: Database Schema & Relational DDL)
-- ============================================================================

-- Ensure the schema exists and set the search path
CREATE SCHEMA IF NOT EXISTS instagram;
SET search_path TO instagram, public;

-- ----------------------------------------------------------------------------
-- Teardown: Drop existing tables in reverse dependency order (child before parent)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS stories CASCADE;
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS likes CASCADE;
DROP TABLE IF EXISTS post_media CASCADE;
DROP TABLE IF EXISTS post_hashtags CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS hashtags CASCADE;
DROP TABLE IF EXISTS follows CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ----------------------------------------------------------------------------
-- 1. USERS
-- Core user account table storing authentication credentials, profile facts,
-- and cached follower/following counts.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id          INTEGER PRIMARY KEY,
    username         VARCHAR(30) NOT NULL UNIQUE
                     CHECK (username ~ '^[a-z0-9._]{1,30}$'),
    full_name        VARCHAR(100) NOT NULL,
    email            VARCHAR(254) NOT NULL UNIQUE,
    bio              TEXT,
    account_type     VARCHAR(10) NOT NULL
                     CHECK (account_type IN ('PERSONAL', 'CREATOR', 'BUSINESS')),
    is_private       BOOLEAN NOT NULL,
    is_verified      BOOLEAN NOT NULL,
    followers_count  INTEGER NOT NULL CHECK (followers_count >= 0),
    following_count  INTEGER NOT NULL CHECK (following_count >= 0),
    created_at       TIMESTAMPTZ NOT NULL,
    CHECK (account_type <> 'BUSINESS' OR NOT is_private)
);

-- ----------------------------------------------------------------------------
-- 2. FOLLOWS
-- Directed social graph relationships between users (M:N self-relationship).
-- Prevents self-follows and tracks acceptance state for private accounts.
-- ----------------------------------------------------------------------------
CREATE TABLE follows (
    follower_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    followee_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    status      VARCHAR(10) NOT NULL CHECK (status IN ('ACCEPTED', 'PENDING')),
    created_at  TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);

-- ----------------------------------------------------------------------------
-- 3. HASHTAGS
-- Global catalog of unique hashtags without the leading '#' symbol.
-- ----------------------------------------------------------------------------
CREATE TABLE hashtags (
    hashtag_id INTEGER PRIMARY KEY,
    tag        VARCHAR(30) NOT NULL UNIQUE
               CHECK (tag ~ '^[a-z0-9_]+$')
);

-- ----------------------------------------------------------------------------
-- 4. POSTS
-- Multi-modal content publications (photos, videos, carousels, reels).
-- ----------------------------------------------------------------------------
CREATE TABLE posts (
    post_id       INTEGER PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    post_type     VARCHAR(10) NOT NULL CHECK (post_type IN ('PHOTO', 'VIDEO', 'CAROUSEL', 'REEL')),
    caption       TEXT,
    location_name VARCHAR(100),
    like_count    INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    is_archived   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 5. POST_HASHTAGS
-- Associative resolution table linking posts and hashtags (M:N relationship).
-- ON DELETE RESTRICT prevents accidental removal of active catalog tags.
-- ----------------------------------------------------------------------------
CREATE TABLE post_hashtags (
    post_id    INTEGER NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    hashtag_id INTEGER NOT NULL REFERENCES hashtags(hashtag_id) ON DELETE RESTRICT,
    PRIMARY KEY (post_id, hashtag_id)
);

-- ----------------------------------------------------------------------------
-- 6. POST_MEDIA
-- Media assets belonging to posts, supporting ordered carousel slides (1-10).
-- Enforces duration validation for video media and prohibits duration for images.
-- ----------------------------------------------------------------------------
CREATE TABLE post_media (
    post_id      INTEGER NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    position     SMALLINT NOT NULL CHECK (position BETWEEN 1 AND 10),
    media_type   VARCHAR(5) NOT NULL CHECK (media_type IN ('IMAGE', 'VIDEO')),
    media_url    TEXT NOT NULL,
    width        SMALLINT NOT NULL CHECK (width > 0),
    height       SMALLINT NOT NULL CHECK (height > 0),
    duration_sec NUMERIC(6,1),
    PRIMARY KEY (post_id, position),
    CHECK ((media_type = 'VIDEO' AND duration_sec IS NOT NULL AND duration_sec > 0)
        OR (media_type = 'IMAGE' AND duration_sec IS NULL))
);

-- ----------------------------------------------------------------------------
-- 7. LIKES
-- Engagement interaction recording user likes on posts (M:N relationship).
-- Composite PK ensures at most one like per user per post.
-- ----------------------------------------------------------------------------
CREATE TABLE likes (
    user_id    INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    post_id    INTEGER NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, post_id)
);

-- ----------------------------------------------------------------------------
-- 8. COMMENTS
-- User comments on posts supporting recursive discussion threads via self-FK.
-- ----------------------------------------------------------------------------
CREATE TABLE comments (
    comment_id        INTEGER PRIMARY KEY,
    post_id           INTEGER NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    user_id           INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    parent_comment_id INTEGER REFERENCES comments(comment_id) ON DELETE CASCADE,
    body              TEXT NOT NULL,
    is_hidden         BOOLEAN NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 9. STORIES
-- Ephemeral 24-hour expiring media stories with view counts.
-- Strict CHECK constraint guarantees exactly 24 hours between creation and expiry.
-- ----------------------------------------------------------------------------
CREATE TABLE stories (
    story_id   INTEGER PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    media_type VARCHAR(5) NOT NULL CHECK (media_type IN ('IMAGE', 'VIDEO')),
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    view_count INTEGER NOT NULL CHECK (view_count >= 0),
    CHECK (expires_at = created_at + INTERVAL '24 hours')
);
