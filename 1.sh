
total_mem_bytes=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)
echo total_mem_bytes $total_mem_bytes

shm_size_gb=$(awk -v mem=$total_mem_bytes 'BEGIN {printf "%.2f", mem * 0.5 / (1024^3)}')
echo shm_size_gb: $shm_size_gb

# Calculate a percentage of shm_size for object-store-memory, e.g., 80% of shm_size
object_store_mem_bytes=$(awk -v shm_bytes=$shm_size_bytes 'BEGIN {printf "%.0f", shm_bytes * 0.8}')

echo object_store_mem_bytes   $object_store_mem_bytes
