-- Set these:
SET @target_database = 'myapp_production';
SET @table_pattern   = 'log_%';               -- NULL = optimize every table in the DB
SET @dry_run         = FALSE;                 -- change to TRUE to test

-- ────────────────────────────────────────────────

SET @tables = NULL;

SELECT GROUP_CONCAT(TABLE_NAME SEPARATOR ', ') INTO @tables
FROM information_schema.tables
WHERE table_schema = @target_database
  AND TABLE_TYPE = 'BASE TABLE'
  AND (@table_pattern IS NULL OR TABLE_NAME LIKE @table_pattern);

IF @tables IS NULL THEN
    SELECT 'No tables matched the criteria.' AS message;
ELSE
    SET @sql = CONCAT('OPTIMIZE TABLE ', @tables);

    IF @dry_run THEN
        SELECT @sql AS 'Dry-run – command that would be executed';
    ELSE
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        SELECT CONCAT('Optimized ', @tables) AS result;
    END IF;
END IF;

-- Cleanup (optional)
SET @tables = NULL;
SET @sql = NULL;