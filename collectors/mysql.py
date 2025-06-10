"""MySQL metrics collector."""
import mysql.connector
import os
import time
import psutil
from influxdb_client import Point
from config import MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, MYSQL_ENABLED, MYSQL_TIMEOUT

# Variables to store previous MySQL metrics for interval calculations
last_mysql_metrics = None
last_collection_time = None
last_mysql_net_io = None
last_mysql_disk_io = None
last_response_times = None

def get_mysql_process_stats():
    """Get MySQL process CPU, memory, and disk I/O stats."""
    mysql_stats = {
        'cpu_percent': 0,
        'memory_percent': 0,
        'disk_read_bytes': 0,
        'disk_write_bytes': 0,
        'net_bytes_sent': 0,
        'net_bytes_recv': 0
    }
    
    try:
        # Find MySQL processes (common process names)
        mysql_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['name'] in ['mysqld', 'mysql'] or \
                   any('mysql' in arg.lower() for arg in (proc.info['cmdline'] or [])):
                    mysql_processes.append(proc)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        
        # Aggregate stats from all MySQL processes
        total_cpu = 0
        total_memory = 0
        total_disk_read = 0
        total_disk_write = 0
        total_net_sent = 0
        total_net_recv = 0
        
        for proc in mysql_processes:
            try:
                # CPU and Memory
                total_cpu += proc.cpu_percent()
                total_memory += proc.memory_percent()
                
                # Disk I/O
                io_counters = proc.io_counters()
                if io_counters:
                    total_disk_read += io_counters.read_bytes
                    total_disk_write += io_counters.write_bytes
                
                # Network connections (approximation)
                connections = proc.connections()
                for conn in connections:
                    if hasattr(conn, 'laddr') and conn.laddr and conn.laddr.port == 3306:
                        # This is a rough approximation - actual network bytes would need to be tracked differently
                        pass
                        
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        
        mysql_stats['cpu_percent'] = total_cpu
        mysql_stats['memory_percent'] = total_memory
        mysql_stats['disk_read_bytes'] = total_disk_read
        mysql_stats['disk_write_bytes'] = total_disk_write
        
    except Exception as e:
        print(f"Error getting MySQL process stats: {e}")
    
    return mysql_stats

def get_mysql_data_directory_size():
    """Get the size of MySQL data directory."""
    data_dir = "/var/lib/mysql"
    log_dir = "/var/log/mysql"
    
    data_size = 0
    log_size = 0
    
    try:
        # Calculate data directory size
        if os.path.exists(data_dir):
            for dirpath, dirnames, filenames in os.walk(data_dir):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    try:
                        data_size += os.path.getsize(filepath)
                    except (OSError, IOError):
                        continue
    except Exception as e:
        print(f"Error calculating MySQL data directory size: {e}")
    
    try:
        # Calculate log directory size
        if os.path.exists(log_dir):
            for dirpath, dirnames, filenames in os.walk(log_dir):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    try:
                        log_size += os.path.getsize(filepath)
                    except (OSError, IOError):
                        continue
    except Exception as e:
        print(f"Error calculating MySQL log directory size: {e}")
    
    return data_size, log_size

def collect_mysql_metrics(host):
    """Collect MySQL metrics from database status and system stats."""
    global last_mysql_metrics, last_collection_time, last_mysql_net_io, last_mysql_disk_io, last_response_times
    mysql_points = []
    
    if not MYSQL_ENABLED:
        return []
    
    current_time = time.time()
    
    try:
        # Connect to MySQL
        connection = mysql.connector.connect(
            host=MYSQL_HOST,
            port=MYSQL_PORT,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DATABASE,
            connection_timeout=MYSQL_TIMEOUT
        )
        cursor = connection.cursor()
        
        # Get MySQL status variables
        cursor.execute("SHOW GLOBAL STATUS")
        status_vars = {row[0]: row[1] for row in cursor.fetchall()}
        
        # Get MySQL system variables for configuration info
        cursor.execute("SHOW GLOBAL VARIABLES LIKE 'max_connections'")
        max_connections = int(cursor.fetchone()[1])
        
        # Get response time distribution from performance schema (if available)
        response_times = {}
        try:
            cursor.execute("""
                SELECT 
                    SUM_TIMER_WAIT/1000000000 as total_time_ms,
                    COUNT_STAR as total_queries,
                    AVG_TIMER_WAIT/1000000000 as avg_response_time_ms,
                    MAX_TIMER_WAIT/1000000000 as max_response_time_ms
                FROM performance_schema.events_statements_summary_global_by_event_name 
                WHERE EVENT_NAME LIKE 'statement/sql/%' 
                AND COUNT_STAR > 0
                ORDER BY COUNT_STAR DESC 
                LIMIT 1
            """)
            result = cursor.fetchone()
            if result:
                response_times = {
                    'total_time_ms': float(result[0]) if result[0] else 0,
                    'total_queries': int(result[1]) if result[1] else 0,
                    'avg_response_time_ms': float(result[2]) if result[2] else 0,
                    'max_response_time_ms': float(result[3]) if result[3] else 0
                }
        except mysql.connector.Error:
            # Performance schema might not be available or accessible
            response_times = {
                'total_time_ms': 0,
                'total_queries': 0,
                'avg_response_time_ms': 0,
                'max_response_time_ms': 0
            }
        
        # Current metrics
        current_metrics = {
            'queries': int(status_vars.get('Queries', 0)),
            'bytes_sent': int(status_vars.get('Bytes_sent', 0)),
            'bytes_received': int(status_vars.get('Bytes_received', 0)),
            'connections': int(status_vars.get('Connections', 0)),
            'threads_connected': int(status_vars.get('Threads_connected', 0)),
            'threads_running': int(status_vars.get('Threads_running', 0)),
            'aborted_connects': int(status_vars.get('Aborted_connects', 0)),
            'aborted_clients': int(status_vars.get('Aborted_clients', 0)),
            'qcache_hits': int(status_vars.get('Qcache_hits', 0)),
            'qcache_queries_in_cache': int(status_vars.get('Qcache_queries_in_cache', 0)),
            'qcache_inserts': int(status_vars.get('Qcache_inserts', 0)),
            'qcache_not_cached': int(status_vars.get('Qcache_not_cached', 0)),
            'innodb_buffer_pool_read_requests': int(status_vars.get('Innodb_buffer_pool_read_requests', 0)),
            'innodb_buffer_pool_reads': int(status_vars.get('Innodb_buffer_pool_reads', 0)),
            'innodb_buffer_pool_pages_total': int(status_vars.get('Innodb_buffer_pool_pages_total', 0)),
            'innodb_buffer_pool_pages_free': int(status_vars.get('Innodb_buffer_pool_pages_free', 0)),
        }
        
        # Get MySQL process system stats
        process_stats = get_mysql_process_stats()
        
        # Get storage sizes
        data_size, log_size = get_mysql_data_directory_size()
        
        # MySQL Health Check
        mysql_points.append(
            Point("mysql_health").tag("host", host)
                .field("is_responsive", 1)  # 1 = healthy
                .field("max_connections", max_connections)
        )
        
        # MySQL Process Resource Usage
        mysql_points.append(
            Point("mysql_resources").tag("host", host)
                .field("cpu_percent", process_stats['cpu_percent'])
                .field("memory_percent", process_stats['memory_percent'])
                .field("data_size_bytes", data_size)
                .field("log_size_bytes", log_size)
        )
        
        # MySQL Connection Status
        idle_connections = current_metrics['threads_connected'] - current_metrics['threads_running']
        mysql_points.append(
            Point("mysql_connections").tag("host", host)
                .field("active_connections", current_metrics['threads_running'])
                .field("idle_connections", idle_connections)
                .field("total_connections", current_metrics['threads_connected'])
                .field("aborted_connects", current_metrics['aborted_connects'])
                .field("aborted_clients", current_metrics['aborted_clients'])
                .field("max_connections", max_connections)
        )
        
        # MySQL Query Cache Hit Ratio
        # Query Cache Hit Ratio = (Qcache_hits) / (Qcache_hits + Qcache_inserts + Qcache_not_cached) * 100
        total_cache_requests = current_metrics['qcache_hits'] + current_metrics['qcache_inserts'] + current_metrics['qcache_not_cached']
        query_cache_hit_ratio = (current_metrics['qcache_hits'] / total_cache_requests * 100) if total_cache_requests > 0 else 0
        
        mysql_points.append(
            Point("mysql_cache").tag("host", host)
                .field("query_cache_hit_ratio", query_cache_hit_ratio)
                .field("queries_in_cache", current_metrics['qcache_queries_in_cache'])
        )
        
        # MySQL InnoDB Buffer Pool Hit Ratio
        # Buffer Pool Hit Ratio = (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100
        buffer_pool_hit_ratio = 0
        if current_metrics['innodb_buffer_pool_read_requests'] > 0:
            buffer_pool_hit_ratio = (1 - (current_metrics['innodb_buffer_pool_reads'] / current_metrics['innodb_buffer_pool_read_requests'])) * 100
        
        buffer_pool_usage = 0
        if current_metrics['innodb_buffer_pool_pages_total'] > 0:
            used_pages = current_metrics['innodb_buffer_pool_pages_total'] - current_metrics['innodb_buffer_pool_pages_free']
            buffer_pool_usage = (used_pages / current_metrics['innodb_buffer_pool_pages_total']) * 100
        
        mysql_points.append(
            Point("mysql_innodb").tag("host", host)
                .field("buffer_pool_hit_ratio", buffer_pool_hit_ratio)
                .field("buffer_pool_usage_percent", buffer_pool_usage)
        )
        
        # MySQL Response Time Distribution (interval-based)
        if last_response_times and last_collection_time:
            time_delta = current_time - last_collection_time
            
            # Calculate deltas for response times
            total_time_delta = response_times['total_time_ms'] - last_response_times['total_time_ms']
            total_queries_delta = response_times['total_queries'] - last_response_times['total_queries']
            
            # Calculate average response time for this interval
            interval_avg_response_time = 0
            if total_queries_delta > 0:
                interval_avg_response_time = total_time_delta / total_queries_delta
            
            # Max response time is tricky with cumulative data - we'll use the current max as an indicator
            # In practice, this will show the highest response time seen since last collection
            interval_max_response_time = response_times['max_response_time_ms']
            
            mysql_points.append(
                Point("mysql_response_times").tag("host", host)
                    .field("interval_avg_response_time_ms", interval_avg_response_time)
                    .field("interval_max_response_time_ms", interval_max_response_time)
                    .field("interval_queries_count", total_queries_delta)
                    .field("interval_total_time_ms", total_time_delta)
            )
        
        # Store current response time metrics for next iteration
        last_response_times = response_times
        
        # MySQL Network Traffic and Queries (interval-based calculations)
        if last_mysql_metrics and last_collection_time:
            time_delta = current_time - last_collection_time
            
            # Calculate deltas for the 30-second window
            queries_delta = current_metrics['queries'] - last_mysql_metrics['queries']
            bytes_sent_delta = current_metrics['bytes_sent'] - last_mysql_metrics['bytes_sent']
            bytes_received_delta = current_metrics['bytes_received'] - last_mysql_metrics['bytes_received']
            
            # Calculate rates per second, then multiply by collection interval for total in window
            if time_delta > 0:
                queries_per_30sec = queries_delta  # This is already the count for our collection window
                bytes_sent_per_second = bytes_sent_delta / time_delta
                bytes_received_per_second = bytes_received_delta / time_delta
                
                mysql_points.append(
                    Point("mysql_performance").tag("host", host)
                        .field("queries_per_30sec", queries_per_30sec)
                        .field("bytes_sent_per_second", bytes_sent_per_second)
                        .field("bytes_received_per_second", bytes_received_per_second)
                )
        
        # MySQL Disk I/O (from process stats)
        if last_mysql_disk_io:
            disk_read_delta = process_stats['disk_read_bytes'] - last_mysql_disk_io['disk_read_bytes']
            disk_write_delta = process_stats['disk_write_bytes'] - last_mysql_disk_io['disk_write_bytes']
            
            time_delta = current_time - last_collection_time if last_collection_time else 30
            
            mysql_points.append(
                Point("mysql_disk_io").tag("host", host)
                    .field("disk_read_per_second", disk_read_delta / time_delta if time_delta > 0 else 0)
                    .field("disk_write_per_second", disk_write_delta / time_delta if time_delta > 0 else 0)
            )
        
        # Store current metrics for next iteration
        last_mysql_metrics = current_metrics
        last_collection_time = current_time
        last_mysql_disk_io = {
            'disk_read_bytes': process_stats['disk_read_bytes'],
            'disk_write_bytes': process_stats['disk_write_bytes']
        }
        
        cursor.close()
        connection.close()
        
    except mysql.connector.Error as e:
        print(f"MySQL connection error: {e}")
        # Add unhealthy status point
        mysql_points.append(
            Point("mysql_health").tag("host", host)
                .field("is_responsive", 0)  # 0 = unhealthy
        )
    except Exception as e:
        print(f"Error collecting MySQL metrics: {e}")
        mysql_points.append(
            Point("mysql_health").tag("host", host)
                .field("is_responsive", 0)  # 0 = unhealthy
        )
    
    return mysql_points

def collect(host):
    """Main collection function for MySQL metrics."""
    return collect_mysql_metrics(host)
