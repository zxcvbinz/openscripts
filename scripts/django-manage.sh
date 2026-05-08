#!/bin/bash

function show_help() {
  echo -e "Usage: $0 <command> [parameters]\n"
  echo "Available commands:"
  printf "  %-40s %s\n" "migrate" "Run makemigrations and migrate"
  printf "  %-40s %s\n" "start" "Start the Django development server"
  printf "  %-40s %s\n" "createsuperuser" "Create a Django superuser"
  printf "  %-40s %s\n" "list" "List migrations (showmigrations)"
  printf "  %-40s %s\n" "sqlmigrate <app_name> <migrate_number>" "Print SQL for a specific migration"
  echo
  echo "Examples:"
  printf "  %s\n" "$0 migrate"
  printf "  %s\n" "$0 start"
  printf "  %s\n" "$0 createsuperuser"
  printf "  %s\n" "$0 list"
  printf "  %s\n" "$0 sqlmigrate myapp 0001"
  echo
  echo "Run from a directory containing manage.py."
  exit 1
}


function migrate() {
  echo "Running database migrations..."
  python manage.py makemigrations
  python manage.py migrate
  echo "Migrations complete."
}

function start() {
  echo "Starting Django application..."
  python manage.py runserver
}

function createsuperuser() {
  echo "Creating Django superuser..."
  python manage.py createsuperuser
}

function list() {
  echo "Listing migrations..."
  python manage.py showmigrations
}

function sqlmigrate() {
  if [ "$#" -ne 3 ]; then
    echo "Correct usage: $0 sqlmigrate <app_name> <migrate_number>"
    exit 1
  fi

  echo "Running sqlmigrate for app $2 and migration $3..."
  python manage.py sqlmigrate "$2" "$3"
}

if [ "$#" -lt 1 ]; then
  show_help
fi

case "$1" in
  migrate)
    migrate
    ;;
  start)
    start
    ;;
  createsuperuser)
    createsuperuser
    ;;
  list)
    list
    ;;
  sqlmigrate)
    sqlmigrate "$@"
    ;;
  *)
    show_help
    ;;
esac
