# Sourced by provision.sh. MariaDB database + user for the site. Re-running resyncs the password.
# Password comes from $SPI_DB_PASSWORD (never argv). Generic name: ${SITE^^}_DB_PASSWORD.
pw_var="${SITE^^}_DB_PASSWORD"
db_password=${!pw_var:-}

if [ -z "$db_password" ]; then
    if mysql -N -e "SELECT 1 FROM mysql.user WHERE user='$DB_USER' AND host='localhost'" 2>/dev/null | grep -q 1; then
        warn "$pw_var not set: database user exists, password left as is"
        db_password=
    else
        die "$pw_var not set and database user $DB_USER does not exist"
    fi
fi

[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ && "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "invalid DB name/user"
if [ -n "$db_password" ]; then
    [[ "$db_password" =~ ^[A-Za-z0-9]{16,}$ ]] || die "$pw_var must be 16+ alphanumeric characters"
fi

{
    echo "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    echo "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '${db_password:-unused-placeholder}';"
    [ -z "$db_password" ] || echo "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$db_password';"
    echo "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    echo "FLUSH PRIVILEGES;"
} | mysql
log "ensured:   database $DB_NAME, user $DB_USER@localhost (grants limited to $DB_NAME.*)"
