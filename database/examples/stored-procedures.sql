-- Veltro stored procedure examples
--
-- DOCUMENTATION ONLY: Docker and Laravel do not load this file automatically.
-- These examples target MySQL 8.0 and the schema in database/veltro-schema.sql.
-- Install them explicitly only in a disposable database:
--   mysql -u root -p < database/examples/stored-procedures.sql

USE `veltro_local`;

DELIMITER $$

-- Adds an active member while enforcing the team's configured capacity.
CREATE PROCEDURE `sp_add_team_member`(
    IN p_team_id BIGINT UNSIGNED,
    IN p_user_id BIGINT UNSIGNED,
    IN p_role VARCHAR(20),
    IN p_position VARCHAR(20)
)
BEGIN
    DECLARE v_team_exists INT DEFAULT 0;
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_max_members INT DEFAULT NULL;
    DECLARE v_active_members INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_role NOT IN ('captain', 'co_captain', 'player') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid team member role';
    END IF;

    IF p_position IS NOT NULL
       AND p_position NOT IN ('goalkeeper', 'defender', 'midfielder', 'forward') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid player position';
    END IF;

    SELECT COUNT(*) INTO v_team_exists FROM teams WHERE id = p_team_id;
    SELECT COUNT(*) INTO v_user_exists FROM users WHERE id = p_user_id;

    IF v_team_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team not found';
    END IF;

    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User not found';
    END IF;

    START TRANSACTION;

    SELECT max_members
      INTO v_max_members
      FROM teams
     WHERE id = p_team_id
       FOR UPDATE;

    SELECT COUNT(*)
      INTO v_active_members
      FROM team_members
     WHERE team_id = p_team_id
       AND status = 'active';

    IF v_max_members IS NOT NULL AND v_active_members >= v_max_members THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team has reached its member limit';
    END IF;

    INSERT INTO team_members (
        user_id, team_id, role, position, joined_at, status, created_at, updated_at
    ) VALUES (
        p_user_id, p_team_id, p_role, p_position, CURRENT_TIMESTAMP,
        'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    );

    COMMIT;

    SELECT LAST_INSERT_ID() AS team_member_id;
END$$

-- Records an event and updates the score atomically when the event is a goal.
CREATE PROCEDURE `sp_record_match_event`(
    IN p_match_id BIGINT UNSIGNED,
    IN p_team_id BIGINT UNSIGNED,
    IN p_user_id BIGINT UNSIGNED,
    IN p_event_type VARCHAR(30),
    IN p_minute INT,
    IN p_description TEXT
)
BEGIN
    DECLARE v_match_exists INT DEFAULT 0;
    DECLARE v_match_status VARCHAR(30);
    DECLARE v_home_team_id BIGINT UNSIGNED;
    DECLARE v_away_team_id BIGINT UNSIGNED;
    DECLARE v_event_id BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_event_type NOT IN (
        'goal', 'assist', 'yellow_card', 'red_card',
        'substitution_in', 'substitution_out'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid match event type';
    END IF;

    IF p_minute IS NOT NULL AND (p_minute < 0 OR p_minute > 200) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid match minute';
    END IF;

    SELECT COUNT(*) INTO v_match_exists FROM matches WHERE id = p_match_id;
    IF v_match_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Match not found';
    END IF;

    START TRANSACTION;

    SELECT status, home_team_id, away_team_id
      INTO v_match_status, v_home_team_id, v_away_team_id
      FROM matches
     WHERE id = p_match_id
       FOR UPDATE;

    IF v_match_status <> 'in_progress' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Match is not in progress';
    END IF;

    IF p_team_id <> v_home_team_id
       AND (v_away_team_id IS NULL OR p_team_id <> v_away_team_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team does not participate in this match';
    END IF;

    IF p_user_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
          FROM team_members
         WHERE team_id = p_team_id
           AND user_id = p_user_id
           AND status = 'active'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User is not an active member of the team';
    END IF;

    INSERT INTO match_events (
        match_id, team_id, user_id, event_type, minute,
        description, created_at, updated_at
    ) VALUES (
        p_match_id, p_team_id, p_user_id, p_event_type, p_minute,
        p_description, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    );

    SET v_event_id = LAST_INSERT_ID();

    IF p_event_type = 'goal' THEN
        UPDATE matches
           SET home_score = home_score + IF(p_team_id = v_home_team_id, 1, 0),
               away_score = away_score + IF(p_team_id = v_away_team_id, 1, 0),
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_match_id;
    END IF;

    COMMIT;

    SELECT v_event_id AS match_event_id, home_score, away_score
      FROM matches
     WHERE id = p_match_id;
END$$

-- Returns a league-style table for approved teams and completed matches.
CREATE PROCEDURE `sp_get_tournament_standings`(
    IN p_tournament_id BIGINT UNSIGNED
)
BEGIN
    WITH results AS (
        SELECT
            tt.team_id,
            COUNT(m.id) AS played,
            SUM(CASE
                WHEN m.id IS NULL THEN 0
                WHEN m.home_team_id = tt.team_id AND m.home_score > m.away_score THEN 1
                WHEN m.away_team_id = tt.team_id AND m.away_score > m.home_score THEN 1
                ELSE 0
            END) AS won,
            SUM(CASE
                WHEN m.id IS NOT NULL AND m.home_score = m.away_score THEN 1
                ELSE 0
            END) AS drawn,
            SUM(CASE
                WHEN m.id IS NULL THEN 0
                WHEN m.home_team_id = tt.team_id AND m.home_score < m.away_score THEN 1
                WHEN m.away_team_id = tt.team_id AND m.away_score < m.home_score THEN 1
                ELSE 0
            END) AS lost,
            SUM(CASE
                WHEN m.home_team_id = tt.team_id THEN m.home_score
                WHEN m.away_team_id = tt.team_id THEN m.away_score
                ELSE 0
            END) AS goals_for,
            SUM(CASE
                WHEN m.home_team_id = tt.team_id THEN m.away_score
                WHEN m.away_team_id = tt.team_id THEN m.home_score
                ELSE 0
            END) AS goals_against
        FROM tournament_teams tt
        LEFT JOIN matches m
          ON m.tournament_id = tt.tournament_id
         AND m.status = 'completed'
         AND (m.home_team_id = tt.team_id OR m.away_team_id = tt.team_id)
        WHERE tt.tournament_id = p_tournament_id
          AND tt.status = 'approved'
        GROUP BY tt.team_id
    )
    SELECT
        t.public_id AS team_public_id,
        t.name AS team_name,
        r.played,
        r.won,
        r.drawn,
        r.lost,
        r.goals_for,
        r.goals_against,
        r.goals_for - r.goals_against AS goal_difference,
        (r.won * 3) + r.drawn AS points
    FROM results r
    JOIN teams t ON t.id = r.team_id
    ORDER BY points DESC, goal_difference DESC, goals_for DESC, team_name ASC;
END$$

DELIMITER ;

-- Example calls (identifiers must exist in the database):
-- CALL sp_add_team_member(1, 10, 'player', 'midfielder');
-- CALL sp_record_match_event(42, 1, 10, 'goal', 67, 'Header from a corner');
-- CALL sp_get_tournament_standings(3);
