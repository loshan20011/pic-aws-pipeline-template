#!/bin/bash

# Define database names and corresponding SQL script paths
declare -A DATABASES
DATABASES=(
    ["userdb"]="./dbscripts/postgresql.sql"
    ["shareddb"]="./dbscripts/postgresql.sql"
    ["consentdb"]="./dbscripts/consent/postgresql.sql ./dbscripts/identity/postgresql.sql"
    ["identitydb"]="./dbscripts/consent/postgresql.sql ./dbscripts/identity/postgresql.sql"
)

# Function to create a database if it doesn't exist
create_database() {
    local DB_NAME=$1
    DB_EXISTS=$(psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$MASTER_DB" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")

    if [[ "$DB_EXISTS" != "1" ]]; then
        echo "Creating database: $DB_NAME"
        psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$MASTER_DB" -c "CREATE DATABASE $DB_NAME;"
    else
        echo "Database '$DB_NAME' already exists. Skipping creation."
    fi
}

# Function to check if a database is empty (no tables)
is_database_empty() {
    local DB_NAME=$1
    TABLE_COUNT=$(psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")

    [[ "$TABLE_COUNT" -eq 0 ]]
}

# Function to populate a database if it's empty
populate_database() {
    local DB_NAME=$1
    local SQL_FILES=${DATABASES[$DB_NAME]}

    if is_database_empty "$DB_NAME"; then
        echo "Database '$DB_NAME' is empty. Populating..."
        for SQL_FILE in $SQL_FILES; do
            if [ -f "$SQL_FILE" ]; then
                psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$DB_NAME" -f "$SQL_FILE"
            else
                echo "Warning: SQL file not found: $SQL_FILE"
            fi
        done
        echo "Database '$DB_NAME' populated successfully."
    else
        echo "Database '$DB_NAME' already contains tables. Skipping population."
    fi
}

# Process each database
for DB_NAME in "${!DATABASES[@]}"; do
    create_database "$DB_NAME"
    populate_database "$DB_NAME"
done

echo "Database creation and population process completed."
