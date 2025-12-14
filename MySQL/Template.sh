/*
===============================================================================
SCRIPT HEADER TEMPLATE
============================
Script Name: [SCRIPT_NAME.sql]
Description: [BRIEF DESCRIPTION OF THE SCRIPT'S PURPOSE AND FUNCTIONALITY]
             [E.g., This script creates the core tables for the user management system,
              including users, roles, and permissions.]

Database: [TARGET_DATABASE_NAME]  -- Specify the database to use, e.g., myapp_db
MySQL Version: [MINIMUM_VERSION]  -- E.g., 8.0 or higher recommended

Created By: [YOUR_NAME] <[YOUR_EMAIL]>
Created On: [YYYY-MM-DD]

Modified By: [MODIFIER_NAME] <[MODIFIER_EMAIL]>
Modified On: [YYYY-MM-DD]
Modification Notes: [BRIEF NOTES ON CHANGES, e.g., Added index on user_email column for query optimization]

Version: [1.0.0]
License: [E.g., MIT License - SEE LICENSE FILE FOR DETAILS]

Dependencies: [LIST ANY REQUIRED EXTENSIONS OR FEATURES, e.g., InnoDB engine support]
Usage: 
    mysql -u [USERNAME] -p [PASSWORD] [DATABASE] < [SCRIPT_NAME.sql]
    Or source this file within a MySQL session: SOURCE [SCRIPT_NAME.sql];

WARNING: [ANY CRITICAL NOTES, e.g., BACKUP YOUR DATABASE BEFORE RUNNING THIS SCRIPT.
          This script drops and recreates tables - data loss possible!]

Changelog:
- [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES, e.g., Initial creation of user tables]
- [YYYY-MM-DD]: [VERSION] - [E.g., Added audit logging table]
===============================================================================
*/

/* 
 * Safety Settings (Optional: Uncomment and adjust as needed)
 * These prevent issues during execution in a live environment.
 */
/*
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO';
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, AUTOCOMMIT=0;
START TRANSACTION;
*/

-- [YOUR SQL CODE GOES HERE]
-- Example:
-- USE [TARGET_DATABASE_NAME];
-- 
-- DROP TABLE IF EXISTS example_table;
-- CREATE TABLE example_table (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     name VARCHAR(255) NOT NULL,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );
-- 
-- INSERT INTO example_table (name) VALUES ('Sample Entry');

/* 
 * Rollback Safety Settings (Optional: Uncomment if using transaction above)
 * Revert settings after script execution.
 */
/*
COMMIT;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET SQL_MODE=@OLD_SQL_MODE;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;
*/

-- End of script