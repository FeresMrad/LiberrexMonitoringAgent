"""Configuration settings for the monitoring agent."""
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Agent ID configuration (constant - not configurable)
AGENT_ID_FILE = "/opt/monitoring-agent/agent-id"

# InfluxDB 2.x details
INFLUXDB_URL = os.getenv("INFLUXDB_URL")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG")
INFLUXDB_BUCKET = os.getenv("INFLUXDB_BUCKET")

# Validate required InfluxDB settings
if not INFLUXDB_URL:
    raise ValueError("INFLUXDB_URL environment variable is required")
if not INFLUXDB_TOKEN:
    raise ValueError("INFLUXDB_TOKEN environment variable is required")
if not INFLUXDB_ORG:
    raise ValueError("INFLUXDB_ORG environment variable is required")
if not INFLUXDB_BUCKET:
    raise ValueError("INFLUXDB_BUCKET environment variable is required")

# Collection interval in seconds (configurable setting, not sensitive)
COLLECTION_INTERVAL = int(os.getenv("COLLECTION_INTERVAL", "30"))

# Apache monitoring configuration (settings, not credentials)
APACHE_STATUS_URL = "http://localhost/server-status?auto"  # Standard Apache status endpoint
APACHE_ENABLED = True  # Can be configured in code if needed
APACHE_TIMEOUT = 5  # Connection timeout in seconds

# MySQL monitoring configuration
MYSQL_HOST = os.getenv("MYSQL_HOST")
MYSQL_PORT = int(os.getenv("MYSQL_PORT")) if os.getenv("MYSQL_PORT") else None
MYSQL_USER = os.getenv("MYSQL_USER")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD")
MYSQL_DATABASE = "information_schema"  # Standard database for monitoring queries
MYSQL_ENABLED = True  # Can be configured in code if needed
MYSQL_TIMEOUT = 5  # Connection timeout in seconds

# Validate MySQL configuration if enabled
if MYSQL_ENABLED:
    if not MYSQL_HOST:
        raise ValueError("MYSQL_HOST environment variable is required when MySQL monitoring is enabled")
    if not MYSQL_PORT:
        raise ValueError("MYSQL_PORT environment variable is required when MySQL monitoring is enabled")
    if not MYSQL_USER:
        raise ValueError("MYSQL_USER environment variable is required when MySQL monitoring is enabled")
    if not MYSQL_PASSWORD:
        raise ValueError("MYSQL_PASSWORD environment variable is required when MySQL monitoring is enabled")

# Remote logging configuration
REMOTE_LOG_SERVER = os.getenv("REMOTE_LOG_SERVER")

# Validate remote logging configuration
if not REMOTE_LOG_SERVER:
    raise ValueError("REMOTE_LOG_SERVER environment variable is required")

# MySQL Setup Instructions (for documentation):
"""
To set up MySQL monitoring:

1. Create a dedicated monitoring user in MySQL:
   mysql -u root -p
   CREATE USER 'monitoring_user'@'localhost' IDENTIFIED BY 'secure_password';
   GRANT PROCESS ON *.* TO 'monitoring_user'@'localhost';
   GRANT SELECT ON performance_schema.* TO 'monitoring_user'@'localhost';
   FLUSH PRIVILEGES;

2. Set environment variables in your .env file:
   MYSQL_USER=monitoring_user
   MYSQL_PASSWORD=secure_password

3. Test the connection:
   mysql -u monitoring_user -p -e "SHOW PROCESSLIST;"
"""
