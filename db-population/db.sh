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
    echo "Checking if database '$DB_NAME' exists..."

    DB_EXISTS=$(psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$MASTER_DB" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")

    if [ "$DB_EXISTS" == "1" ]; then
        echo "Database '$DB_NAME' already exists, skipping creation."
    else
        echo "Creating database: $DB_NAME"
        psql -q --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --no-password --dbname="$MASTER_DB" -c "CREATE DATABASE $DB_NAME;"
        echo "Database '$DB_NAME' created successfully."
    fi
}

# Function to populate a database with its SQL scripts
populate_database() {
    local DB_NAME=$1
    local SQL_FILES=${DATABASES[$DB_NAME]}

    echo "Populating database: $DB_NAME"
    for SQL_FILE in $SQL_FILES; do
        if [ -f "$SQL_FILE" ]; then
            echo "Applying SQL file: $SQL_FILE"
            psql -q --host="$RDS_HOST" --port="5432" --no-password --username="$MASTER_USERNAME" --dbname="$DB_NAME" -f "$SQL_FILE"
        else
            echo "Warning: SQL file not found: $SQL_FILE"
        fi
    done
    echo "Database '$DB_NAME' populated successfully."
}

# Iterate through the databases and process each one
for DB_NAME in "${!DATABASES[@]}"; do
    create_database "$DB_NAME"
    populate_database "$DB_NAME"
done

echo "All databases are created and populated successfully!"
