#!/bin/bash

for DB_NAME in userdb shareddb consentdb; do
    echo "Creating database: $DB_NAME"
    psql --host="$RDS_HOST" --port="5432" --username="$MASTER_USERNAME" --dbname="$MASTER_DB" -c "CREATE DATABASE $DB_NAME;"
done