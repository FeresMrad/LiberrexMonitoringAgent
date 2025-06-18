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
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "")  # Default to empty string, not None
MYSQL_DATABASE = "information_schema"  # Standard database for monitoring queries
MYSQL_TIMEOUT = 5  # Connection timeout in seconds

# Determine if MySQL monitoring should be enabled based on available credentials
# MySQL is enabled if we have at least HOST, PORT, and USER
# PASSWORD can be empty (for servers that don't require passwords)
if MYSQL_HOST and MYSQL_PORT and MYSQL_USER:
    MYSQL_ENABLED = True
    print(f"MySQL monitoring enabled: {MYSQL_USER}@{MYSQL_HOST}:{MYSQL_PORT}")
    if not MYSQL_PASSWORD:
        print("MySQL monitoring: Using empty password (passwordless connection)")
else:
    MYSQL_ENABLED = False
    print("MySQL monitoring disabled: Missing required credentials (HOST, PORT, USER)")
    if not MYSQL_HOST:
        print("  - Missing MYSQL_HOST")
    if not MYSQL_PORT:
        print("  - Missing MYSQL_PORT") 
    if not MYSQL_USER:
        print("  - Missing MYSQL_USER")

# Remote logging configuration
REMOTE_LOG_SERVER = os.getenv("REMOTE_LOG_SERVER")

# Validate remote logging configuration
if not REMOTE_LOG_SERVER:
    raise ValueError("REMOTE_LOG_SERVER environment variable is required")

# MySQL Setup Instructions (for documentation):
"""
To set up MySQL monitoring:

1. For MySQL servers WITH passwords:
   mysql -u root -p
   CREATE USER 'monitoring_user'@'localhost' IDENTIFIED BY 'secure_password';
   GRANT PROCESS ON *.* TO 'monitoring_user'@'localhost';
   GRANT SELECT ON performance_schema.* TO 'monitoring_user'@'localhost';
   FLUSH PRIVILEGES;

   Set in .env:
   MYSQL_USER=monitoring_user
   MYSQL_PASSWORD=secure_password

2. For MySQL servers WITHOUT passwords:
   mysql -u root
   GRANT PROCESS ON *.* TO 'root'@'localhost';
   GRANT SELECT ON performance_schema.* TO 'root'@'localhost';
   FLUSH PRIVILEGES;

   Set in .env:
   MYSQL_USER=root
   MYSQL_PASSWORD=
   (or omit MYSQL_PASSWORD entirely)

3. Test the connection:
   mysql -u monitoring_user -p -e "SHOW PROCESSLIST;"
   or
   mysql -u root -e "SHOW PROCESSLIST;"
"""
