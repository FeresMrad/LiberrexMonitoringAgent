"""Configuration settings for the monitoring agent."""
import os

# Agent ID configuration
AGENT_ID_FILE = "/opt/monitoring-agent/agent-id"

# InfluxDB 2.x details
INFLUXDB_URL = "http://82.165.230.7:8086"
INFLUXDB_TOKEN = "YnymHsvPMle5ppoGZKDLegZTHyypPtoJFW1sXRWdSH2paW-n24Io45vNObLHlfheaWDAT0e94OfMkRmOcRHmFw=="
INFLUXDB_ORG = "liberrex"
INFLUXDB_BUCKET = "metrics"

# Collection interval in seconds
COLLECTION_INTERVAL = 30

# Apache monitoring configuration
APACHE_STATUS_URL = "http://localhost/server-status?auto"
APACHE_ENABLED = True  # Set to False to disable Apache monitoring
APACHE_TIMEOUT = 5  # Timeout for Apache status request in seconds

# MySQL monitoring configuration
# IMPORTANT: Fill these fields before running install.sh
MYSQL_HOST = "localhost"
MYSQL_PORT = 3306
MYSQL_USER = "root"  # REQUIRED: Set your MySQL monitoring user here
MYSQL_PASSWORD = "LibeRRex@25"  # REQUIRED: Set your MySQL monitoring password here
MYSQL_DATABASE = "information_schema"  # Use information_schema for monitoring queries
MYSQL_ENABLED = True  # Set to False to disable MySQL monitoring
MYSQL_TIMEOUT = 5  # Timeout for MySQL connection in seconds

# MySQL Setup Instructions:
# 1. Create a dedicated monitoring user in MySQL:
#    mysql -u root -p
#    CREATE USER 'your_monitoring_user'@'localhost' IDENTIFIED BY 'your_secure_password';
#    GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'your_monitoring_user'@'localhost';
#    GRANT SELECT ON performance_schema.* TO 'your_monitoring_user'@'localhost';
#    FLUSH PRIVILEGES;
#
# 2. Set MYSQL_USER and MYSQL_PASSWORD above to match your created user
#
# 3. Test the connection:
#    mysql -u your_monitoring_user -p -e "SHOW PROCESSLIST;"
#
# 4. Run install.sh
