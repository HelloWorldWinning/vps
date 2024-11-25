#!/bin/bash

# Get user_id and feature_id
user_info=$(docker exec affine_postgres psql -U affine -t -c "SELECT id FROM users LIMIT 1;" | tr -d ' ')
feature_info=$(docker exec affine_postgres psql -U affine -t -c "SELECT feature_id FROM user_features WHERE feature_id IN (13,14) LIMIT 1;" | tr -d ' ')

# Show current quota
current_quota=$(docker exec affine_postgres psql -U affine -t -c "SELECT configs->>'storageQuota' FROM features WHERE id=$feature_info;" | tr -d ' ')
echo "Current Cloud Storage: $((current_quota/1024/1024/1024))GB"

# Get input with 5s timeout
read -t 5 -p "Enter new storage quota in GB [177]: " new_gb
new_gb=${new_gb:-177}
new_bytes=$((new_gb * 1024 * 1024 * 1024))

# Update quota
docker exec affine_postgres psql -U affine -c "UPDATE features SET configs = 
'{\"name\":\"Pro\",\"blobLimit\":104857600,\"storageQuota\":${new_bytes},\"historyPeriod\":2592000000,\"memberLimit\":10,\"copilotActionLimit\":10}' 
WHERE id=14;"

# Update user's feature to pro plan
docker exec affine_postgres psql -U affine -c "UPDATE user_features SET feature_id = 14 WHERE user_id = '$user_info' AND feature_id = $feature_info;"

echo "Updated Cloud Storage to ${new_gb}GB"
echo "Please restart Docker to apply changes"
