#!/bin/bash
# MIRROR of /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_tinysite.sh (2026-07-18)
# NOTE: despite the filename, this dumps POSTGRES. No credentials in this script
# (pg trust auth inside the container). See README.md.

# Configuration
DB_NAME="tinysite"
DB_USER="postgres"
DOCKER_CONTAINER_NAME="prod-database-tinysite"

# AWS S3 configuration
S3_BUCKET="{{BACKUP_BUCKET_TINYSITE}}"
S3_PATH="backups/postgresql"

# Backup directory
BACKUP_DIR="./tinysite"
mkdir -p $BACKUP_DIR

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="backup_${DB_NAME}_${TIMESTAMP}.sql"
ZIPPED_BACKUP_FILENAME="${BACKUP_FILENAME}.gz"

# Log functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Error handling
set -e
trap 'log_error "Error occurred on line $LINENO. Exit code: $?"' ERR

# Function to check if Docker container is running and accessible
check_docker_container() {
    log "Checking Docker container status..."
    if ! docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        log_error "Docker container '$DOCKER_CONTAINER_NAME' is not running"
        return 1
    fi

    # Test PostgreSQL connection inside container
    if ! docker exec "$DOCKER_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c '\q' &>/dev/null; then
        log_error "Cannot connect to PostgreSQL inside container"
        return 1
    fi

    log "Docker container and PostgreSQL connection verified"
    return 0
}

# Function to verify backup file
verify_backup() {
    local backup_file="$1"

    # Check if file exists and is not empty
    if [ ! -s "$backup_file" ]; then
        log_error "Backup file is empty or does not exist"
        return 1
    fi

    # For uncompressed backup, check if it's a valid PostgreSQL dump
    if [[ $backup_file != *.gz ]]; then
        if ! grep -q "PostgreSQL database dump complete" "$backup_file"; then
            log_error "Backup file does not contain valid PostgreSQL dump"
            return 1
        fi
    fi

    # Get file size
    local file_size
    if [ "$(uname)" == "Darwin" ]; then
        file_size=$(stat -f%z "$backup_file")
    else
        file_size=$(stat -c%s "$backup_file")
    fi
    log "Backup size: $file_size bytes"

    # Check minimum expected size (1KB)
    if [ "$file_size" -lt 1024 ]; then
        log_error "Backup file suspiciously small (< 1KB)"
        return 1
    fi

    return 0
}

# Function to verify S3 upload
verify_s3_upload() {
    local s3_path="$1"
    local local_file="$2"

    # Get local file checksum
    local local_md5
    if [ "$(uname)" == "Darwin" ]; then
        local_md5=$(md5 -q "$local_file")
    else
        local_md5=$(md5sum "$local_file" | awk '{print $1}')
    fi

    # Get S3 file checksum
    local s3_md5
    s3_md5=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_path" --query 'ETag' --output text | tr -d '"')

    if [ "$local_md5" = "$s3_md5" ]; then
        log "S3 upload verified successfully (checksums match)"
        return 0
    else
        log_error "S3 upload verification failed (checksums do not match)"
        return 1
    fi
}

# Main execution
main() {
    # Check Docker container
    if ! check_docker_container; then
        exit 1
    fi

    # Create backup
    log "Starting database backup..."
    if ! (docker exec \
        -t "$DOCKER_CONTAINER_NAME" \
        pg_dump -c \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -F p) >"$BACKUP_DIR/$BACKUP_FILENAME" 2>"$BACKUP_DIR/pg_dump_error.log"; then

        log_error "Database backup failed. Error log:"
        cat "$BACKUP_DIR/pg_dump_error.log"
        exit 1
    fi

    # Verify uncompressed backup
    log "Verifying backup file..."
    if ! verify_backup "$BACKUP_DIR/$BACKUP_FILENAME"; then
        exit 1
    fi

    # Compress backup
    log "Compressing backup..."
    if ! gzip -f "$BACKUP_DIR/$BACKUP_FILENAME"; then
        log_error "Compression failed"
        exit 1
    fi

    # Verify compressed backup
    if ! verify_backup "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME"; then
        exit 1
    fi

    # Upload to S3
    log "Uploading to S3..."
    local s3_key="$S3_PATH/$ZIPPED_BACKUP_FILENAME"
    if ! aws s3 cp "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME" "s3://$S3_BUCKET/$s3_key"; then
        log_error "S3 upload failed"
        exit 1
    fi

    # Verify S3 upload
    log "Verifying S3 upload..."
    if ! verify_s3_upload "$s3_key" "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME"; then
        exit 1
    fi

    # Clean up local backup
    log "Cleaning up local backup..."
    rm -f "$BACKUP_DIR/$BACKUP_FILENAME" "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME" "$BACKUP_DIR/pg_dump_error.log"

    log "Backup process completed successfully"
    return 0
}

# Execute main function
main
