#!/bin/bash

# Super simple Apache LogFormat fix - just add %v where missing

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

APACHE_CONFIG_FILE="/etc/apache2/apache2.conf"

echo "=== BEFORE CHANGES ==="
grep "^LogFormat" "$APACHE_CONFIG_FILE"

echo ""
echo "=== MAKING CHANGES ==="

# Create backup
BACKUP_FILE="/etc/apache2/apache2.conf.backup.$(date +%Y%m%d_%H%M%S)"
cp "$APACHE_CONFIG_FILE" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Fix combined format - add %v at the start
if grep -q 'LogFormat "%h %l %u %t' "$APACHE_CONFIG_FILE"; then
    echo "Adding %v to combined format..."
    sed -i 's/LogFormat "%h %l %u %t/LogFormat "%v %h %l %u %t/' "$APACHE_CONFIG_FILE"
    echo "✓ Combined format updated"
else
    echo "- Combined format already has %v or not found"
fi

# Fix common format - add %v at the start
if grep -q 'LogFormat "%h %l %u %t.*" common' "$APACHE_CONFIG_FILE"; then
    echo "Adding %v to common format..."
    sed -i 's/LogFormat "%h %l %u %t \(.*\)" common/LogFormat "%v %h %l %u %t \1" common/' "$APACHE_CONFIG_FILE"
    echo "✓ Common format updated"
else
    echo "- Common format already has %v or not found"
fi

echo ""
echo "=== AFTER CHANGES ==="
grep "^LogFormat" "$APACHE_CONFIG_FILE"

echo ""
echo "=== TESTING APACHE CONFIG ==="
if apache2ctl configtest; then
    echo "✓ Apache configuration is valid"
    echo ""
    echo "Restarting Apache..."
    if systemctl restart apache2; then
        echo "✓ Apache restarted successfully"
        sleep 2
        if systemctl is-active --quiet apache2; then
            echo "✓ Apache is running"
        else
            echo "✗ Apache is not running"
        fi
    else
        echo "✗ Apache restart failed"
    fi
else
    echo "✗ Apache configuration test failed - restoring backup"
    cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
fi
