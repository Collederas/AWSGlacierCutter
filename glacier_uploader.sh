#!/bin/bash

# Variables
PART_SIZE=134217728
PREFIX="chunk"

# Prompt the user for Vault Name and Account ID
read -p "Enter path to file: " FILE_TO_UPLOAD
read -p "Enter your Glacier Vault Name: " VAULT_NAME
read -p "Enter your AWS Account ID: " ACCOUNT_ID

PREFIX="chunk"

# Install dependencies
pip install treehash


# Split the file
split -b $PART_SIZE $FILE_TO_UPLOAD $PREFIX

# Initiate multipart upload
INITIATE_RESPONSE=$(aws glacier initiate-multipart-upload --vault-name $VAULT_NAME --part-size $PART_SIZE --account-id $ACCOUNT_ID)
UPLOAD_ID=$(echo $INITIATE_RESPONSE | jq -r '.uploadId')

if [ -z "$UPLOAD_ID" ]; then
  echo "Error initiating multipart upload"
  echo "Upload id: $UPLOAD_ID"
  exit 1
fi

# Upload parts
PART_NUMBER=1
START_BYTE=0

for PART_FILE in ${PREFIX}*; do
  # Calculate part size
  CURRENT_PART_SIZE=$(wc -c < "$PART_FILE")
  END_BYTE=$((START_BYTE + CURRENT_PART_SIZE - 1))

  echo "Uploading part $PART_NUMBER: $PART_FILE"

  UPLOAD_PART_RESPONSE=$(aws glacier upload-multipart-part --body $PART_FILE --range "bytes $START_BYTE-$END_BYTE/*" --vault-name $VAULT_NAME --account-id $ACCOUNT_ID --upload-id $UPLOAD_ID)

  if [ $? -ne 0 ]; then
    echo "Error uploading part $PART_NUMBER: $PART_FILE"
    exit 1
  fi

  PART_NUMBER=$((PART_NUMBER+1))
  START_BYTE=$((START_BYTE + CURRENT_PART_SIZE))
done


# Complete multipart upload
ARCHIVE_SIZE=$(wc -c < "$FILE_TO_UPLOAD")
COMPUTE_CHECKSUMS_RESPONSE=$(treehash $FILE_TO_UPLOAD)
TREE_HASH=$(echo $COMPUTE_CHECKSUMS_RESPONSE | awk '{print $2}')

aws glacier complete-multipart-upload --vault-name $VAULT_NAME --account-id $ACCOUNT_ID --upload-id $UPLOAD_ID --archive-size $ARCHIVE_SIZE --checksum $TREE_HASH

# Remove the chunks
rm -f ${PREFIX}*
