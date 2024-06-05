#!/bin/bash

PROJECT_FOLDER=${PROJECT_FOLDER:-~/project}
PROJECT_NAME=${PROJECT_NAME:-project}
PROJECT_NAME=$(echo $PROJECT_NAME | sed 's/[^a-zA-Z0-9]/_/g')

DB_HOST=${DB_HOST-}
DB_PORT=${DB_PORT:-3306}
DB_USER=${DB_USER:-root}
DB_PASSWORD=${DB_PASSWORD:-password}
DB_DATABASE=${DB_DATABASE:-$PROJECT_NAME}

# If the DB_HOST is set and the DB_USER is root, attempt to connect to the database and create the database if it doesn't exist
if [[ -n $DB_HOST && $DB_USER == "root" ]]; then
	RES=0
	mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $PROJECT_NAME;" 2>/dev/null
	RES=$?

	# If the user is root, create a new user with a random password and grant all privileges on the database
	DB_USER_PASSWORD=$(openssl rand -base64 12)
	mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "CREATE USER IF NOT EXISTS '$PROJECT_NAME'@'%' IDENTIFIED BY '$DB_USER_PASSWORD';" 2>/dev/null
	RES=$((RES + $?))
	mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "GRANT ALL PRIVILEGES ON $PROJECT_NAME.* TO '$PROJECT_NAME'@'%';" 2>/dev/null
	RES=$((RES + $?))
	mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "FLUSH PRIVILEGES;" 2>/dev/null
	RES=$((RES + $?))

	# If any of the commands failed, output an error message
	if [[ $RES -ne 0 ]]; then
		echo "Failed to initialise the database, continuing without connection."
	else
		# Output the database details
		echo "Initialised database using root user:"
		echo "Host: $DB_HOST"
		echo "Port: $DB_PORT"
		echo "User: $DB_USER"
		echo "Password: $DB_USER_PASSWORD"
		echo "Database: $PROJECT_NAME"

		# Set the DB_USER and DB_PASSWORD to the new user and password
		DB_USER=$PROJECT_NAME
		DB_PASSWORD=$DB_USER_PASSWORD
		export DB_USER
		export DB_PASSWORD
	fi
fi

# Link apache to $PROJECT_FOLDER
sudo rm -rf /var/www/html
sudo ln -s "${PROJECT_FOLDER}" /var/www/html

# Start Apache
sudo service apache2 start

echo "echo -e 'You are currently running a \033[1;36mPHP\033[0m generic container.'" >>~/.bashrc

# Set up the PHP project
cd "${PROJECT_FOLDER}" || exit

# If the project contains a composer-lock.json file, install the dependencies
if [[ -f composer.lock ]]; then
	composer install -n &
fi

# If the project contains a .env.* file that doesn't include the word 'test', copy it to .env
for file in .env.*; do
	if [[ -f $file ]] && ! grep -q 'test' "$file"; then
		cp "$file" .env
		break
	fi
done
