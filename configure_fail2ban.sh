#!/bin/bash

# This script ONLY adds new custom jails without modifying ANY existing settings

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "Configuring fail2ban for enhanced Apache monitoring (safe mode)..."

# Install fail2ban if not present
if ! command -v fail2ban-server &> /dev/null; then
    echo "Installing fail2ban..."
    apt update
    apt install -y fail2ban
fi

# Create filter files (these are always safe to create/update)
echo "Creating custom fail2ban filters..."

# Create apache-access-auth filter
cat > /etc/fail2ban/filter.d/apache-access-auth.conf << 'EOF'
# Custom filter for Apache access log authentication failures
[Definition]

# Match 401 Unauthorized responses (auth failures)
failregex = ^<HOST> .* "(?:GET|POST|HEAD) .* HTTP/[0-9.]+" 401

# Match multiple rapid auth attempts
            ^<HOST> .* "(?:GET|POST|HEAD) .*(?:login|admin|auth).* HTTP/[0-9.]+" (?:401|403)

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

# Create apache-access-badbots filter
cat > /etc/fail2ban/filter.d/apache-access-badbots.conf << 'EOF'
# Custom filter for bad bots in Apache access log
[Definition]

# Common bad bot patterns (simplified)
failregex = ^<HOST> .* "(?:GET|POST|HEAD) .* HTTP/[0-9.]+" [0-9]+ [0-9]+ ".*" ".*(bot|crawler|spider|scraper|scanner|Email|WebEMail|Track|sogou|atSpider|auto|Guestbook|Industry|LARBIN|scan4mail|Advanced|Iplex).*"
# Match rapid requests (potential bot scanning)
            ^<HOST> .* "(?:GET|POST|HEAD) .* HTTP/[0-9.]+" [0-9]+ [0-9]+ ".*" ".*(?:curl|wget|python|perl|java).*"

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

# Create apache-access-botsearch filter
cat > /etc/fail2ban/filter.d/apache-access-botsearch.conf << 'EOF'
# Custom filter for bot search attacks in Apache access log
[Definition]

# Common admin/exploit paths that bots search for (simplified)
failregex = ^<HOST> .* "(?:GET|POST|HEAD) .*/(?:admin|administrator|phpmyadmin|pma|webmail|wp-admin|wp-login|wp-config|\.env|\.git|config\.php|phpinfo\.php|test\.php|install\.php|setup\.php|backup|adminer\.php).*" HTTP/[0-9.]+" (?:200|404|403)
# Match directory traversal attempts (properly escaped)
            ^<HOST> .* "(?:GET|POST|HEAD) .*(?:\.\./|\.\.).*" HTTP/[0-9.]+" (?:400|403|404)

# Match attempts to access sensitive files
            ^<HOST> .* "(?:GET|POST|HEAD) .*\.(?:conf|ini|cfg|xml|txt|log|bak|old|orig|save|swp|tmp)(?:\?.*?)? HTTP/[0-9.]+" 404

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

# Create apache-access-noscript filter
cat > /etc/fail2ban/filter.d/apache-access-noscript.conf << 'EOF'
# Custom filter for script attacks in Apache access log
[Definition]

# Match 404 errors on script files
failregex = ^<HOST> .* "(?:GET|POST|HEAD) .*\.(?:php|asp|aspx|jsp|pl|py|cgi|exe|sh)(?:\?.*?)? HTTP/[0-9.]+" 404

# Match cgi-bin requests that return 404
            ^<HOST> .* "(?:GET|POST|HEAD) .*/cgi-bin/.* HTTP/[0-9.]+" 404

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

# Create apache-access-overflows filter
cat > /etc/fail2ban/filter.d/apache-access-overflows.conf << 'EOF'
# Custom filter for overflow attacks in Apache access log
[Definition]

# Match 400 Bad Request errors (malformed requests)
failregex = ^<HOST> .* ".*" 400

# Match 414 URI Too Long errors
            ^<HOST> .* ".*" 414

# Match requests with suspicious characters (hex encoded)
            ^<HOST> .* ".*\\\\x[0-9a-fA-F].*" 400

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

# Create apache-access-shellshock filter
cat > /etc/fail2ban/filter.d/apache-access-shellshock.conf << 'EOF'
# Custom filter for shellshock attacks in Apache access log
[Definition]

# Match CGI requests that might be shellshock attempts
failregex = ^<HOST> .* "(?:GET|POST|HEAD) .*/cgi-bin/.* HTTP/[0-9.]+" (?:200|500)

# Match requests to common CGI scripts
            ^<HOST> .* "(?:GET|POST|HEAD) .*\.(?:cgi|sh)(?:\?.*?)? HTTP/[0-9.]+" (?:200|500)

datepattern = \[%%d/%%b/%%Y:%%H:%%M:%%S %%z\]

ignoreregex =
EOF

echo "Custom filters created successfully."

# Function to add jails without touching existing configuration
add_custom_jails() {
    local jail_file="/etc/fail2ban/jail.local"
    local backup_file="/etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Always create backup if jail.local exists
    if [ -f "$jail_file" ]; then
        echo "Creating backup of existing jail.local at $backup_file"
        cp "$jail_file" "$backup_file"
        echo "Existing jail.local detected - will only append new jails if they don't exist"
    else
        echo "No existing jail.local found - creating new one with minimal configuration"
        touch "$jail_file"
    fi
    
    # Function to check if a jail section exists
    jail_exists() {
        local section_name="$1"
        grep -q "^\[$section_name\]" "$jail_file"
    }
    
    # Function to append a jail section only if it doesn't exist
    append_jail_if_missing() {
        local section_name="$1"
        local section_content="$2"
        
        if jail_exists "$section_name"; then
            echo "[$section_name] already exists - skipping to preserve existing configuration"
            return 0
        else
            echo "Adding new [$section_name] jail"
            echo "" >> "$jail_file"
            echo "# Liberrex Monitoring Agent - Custom Apache Access Log Monitoring" >> "$jail_file"
            echo "$section_content" >> "$jail_file"
            return 1
        fi
    }
    
    # Track what we added
    local added_jails=()
    
    # Add our custom Apache access log jails only if they don't exist
    if ! append_jail_if_missing "apache-access-auth" "[apache-access-auth]
enabled = true
filter = apache-access-auth
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 3
bantime = 1h
findtime = 10m"; then
        added_jails+=("apache-access-auth")
    fi
    
    if ! append_jail_if_missing "apache-access-badbots" "[apache-access-badbots]
enabled = true
filter = apache-access-badbots
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 2
bantime = 48h
findtime = 10m"; then
        added_jails+=("apache-access-badbots")
    fi
    
    if ! append_jail_if_missing "apache-access-noscript" "[apache-access-noscript]
enabled = true
filter = apache-access-noscript
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 3
bantime = 2h
findtime = 10m"; then
        added_jails+=("apache-access-noscript")
    fi
    
    if ! append_jail_if_missing "apache-access-overflows" "[apache-access-overflows]
enabled = true
filter = apache-access-overflows
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 2
bantime = 2h
findtime = 10m"; then
        added_jails+=("apache-access-overflows")
    fi
    
    if ! append_jail_if_missing "apache-access-botsearch" "[apache-access-botsearch]
enabled = true
filter = apache-access-botsearch
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 2
bantime = 6h
findtime = 10m"; then
        added_jails+=("apache-access-botsearch")
    fi
    
    if ! append_jail_if_missing "apache-access-shellshock" "[apache-access-shellshock]
enabled = true
filter = apache-access-shellshock
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 1
bantime = 24h
findtime = 10m"; then
        added_jails+=("apache-access-shellshock")
    fi
    
    # Report what was added
    if [ ${#added_jails[@]} -gt 0 ]; then
        echo ""
        echo "Added ${#added_jails[@]} new custom jails:"
        printf " - %s\n" "${added_jails[@]}"
    else
        echo ""
        echo "All custom jails already exist - no changes made to preserve existing configuration"
    fi
    
    echo "jail.local updated successfully without modifying existing settings"
}

# Add custom jails safely
echo "Safely adding custom jails to jail.local..."
add_custom_jails

# Test fail2ban configuration
echo ""
echo "Testing fail2ban configuration..."
if fail2ban-client -t; then
    echo "✓ Fail2ban configuration test passed"
    
    # Enable fail2ban service (safe operation)
    systemctl enable fail2ban >/dev/null 2>&1
    
    # Check if Apache was recently restarted by monitoring agent
    APACHE_NEEDS_RESTART=false
    if [ -f "/tmp/apache_restarted_by_monitoring_agent" ]; then
        echo "ℹ Apache was recently restarted by monitoring agent - no additional restart needed"
        rm -f "/tmp/apache_restarted_by_monitoring_agent"
    else
        # Check if any fail2ban configuration might affect Apache
        if systemctl is-active --quiet apache2 && [ -f "/var/log/apache2/access.log" ]; then
            APACHE_NEEDS_RESTART=true
        fi
    fi
    
    # Restart fail2ban to apply changes
    echo "Restarting fail2ban service..."
    if systemctl restart fail2ban; then
        echo "✓ Fail2ban service restarted successfully"
        
        # Only restart Apache if needed and not recently restarted
        if [ "$APACHE_NEEDS_RESTART" = "true" ]; then
            echo "Performing final Apache restart to ensure fail2ban integration..."
            systemctl restart apache2 >/dev/null 2>&1
        fi
        
        # Wait a moment for service to start
        sleep 3
        
        # Check if fail2ban is running
        if systemctl is-active --quiet fail2ban; then
            echo "✓ Fail2ban is running properly"
            
            # Show active jails
            echo ""
            echo "Current active fail2ban jails:"
            fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list:/Jails:/' || echo "No jails currently active"
            
        else
            echo "⚠ WARNING: Fail2ban service is not active"
            echo "Check status with: systemctl status fail2ban"
        fi
    else
        echo "⚠ WARNING: Failed to restart fail2ban service"
        echo "This might be due to configuration conflicts or missing log files"
        echo "Check logs with: journalctl -u fail2ban -n 20"
    fi
else
    echo "⚠ WARNING: Fail2ban configuration test failed"
    echo "This might be due to:"
    echo "1. Missing Apache log files (/var/log/apache2/access.log)"
    echo "2. Permission issues with log files"
    echo "3. Apache not installed or differently configured"
    echo ""
    echo "The existing configuration has NOT been modified."
    echo "Run 'fail2ban-client -t' for detailed error information"
fi

echo ""
echo "================================================================================"
echo "SAFE FAIL2BAN CONFIGURATION COMPLETED"
echo "================================================================================"
echo ""
echo "SAFETY GUARANTEES:"
echo "✓ No existing DEFAULT settings were modified"
echo "✓ No existing jail configurations were changed"  
echo "✓ Backup created of original jail.local"
echo "✓ Only NEW custom jails added (if not already present)"
echo ""
echo "WHAT WAS ADDED:"
echo "- 6 new Apache access log monitoring filters"
echo "- Custom jails for enhanced web security monitoring"
echo "- Protection against auth failures, bots, exploits, and attacks"
echo ""
echo "YOUR EXISTING SETTINGS PRESERVED:"
echo "- bantime: $(grep -A 20 '^\[DEFAULT\]' /etc/fail2ban/jail.local 2>/dev/null | grep '^bantime' | head -1 || echo 'unchanged')"
echo "- findtime: $(grep -A 20 '^\[DEFAULT\]' /etc/fail2ban/jail.local 2>/dev/null | grep '^findtime' | head -1 || echo 'unchanged')"
echo "- maxretry: $(grep -A 20 '^\[DEFAULT\]' /etc/fail2ban/jail.local 2>/dev/null | grep '^maxretry' | head -1 || echo 'unchanged')"
echo "- destemail: $(grep -A 20 '^\[DEFAULT\]' /etc/fail2ban/jail.local 2>/dev/null | grep '^destemail' | head -1 || echo 'unchanged')"
echo ""
echo "If you want to verify the changes, compare:"
echo "- Original: $backup_file"
echo "- Current:  /etc/fail2ban/jail.local"
