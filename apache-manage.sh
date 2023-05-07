#!/bin/bash

# Check if script is being run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: script must be run as root." >&2
    exit 1
fi

# Display selection menu
echo "Select an option:"
echo "1. Create a new site"
echo "2. Show enabled sites"
echo "3. Remove a site"
echo "----------------------------------------------"
read -p "Enter the number of the chosen option: " menu_choice

if [ "$menu_choice" -eq 1 ]; then
    # Read parameters
    read -p "Enter the site name: " site_name
    read -p "Enter the site folder path or reverse proxy address: " site_location
    read -p "Is this configuration a folder (C) or a reverse proxy (R)? [C/R]: " site_type

    # Create log folder
    log_dir="/var/log/apache2/$site_name"
    mkdir -p "$log_dir"

    # Prepare configuration file
    config_file="/etc/apache2/sites-available/$site_name.conf"

    if [ "$site_type" = "C" ] || [ "$site_type" = "c" ]; then
        # Configuration for a folder
        cat >"$config_file" <<EOL
<VirtualHost *:80>
    ServerName $site_name
    DocumentRoot $site_location

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined
</VirtualHost>
EOL
    elif [ "$site_type" = "R" ] || [ "$site_type" = "r" ]; then
        # Configuration for a reverse proxy
        cat >"$config_file" <<EOL
<VirtualHost *:80>
    ServerName $site_name

    ProxyPass / http://$site_location/
    ProxyPassReverse / http://$site_location/

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined
</VirtualHost>
EOL
    else
        echo "Error: Invalid configuration type. Use 'C' for a folder or 'R' for a reverse proxy." >&2
        exit 1
    fi

    # Enable site
    a2ensite "$site_name"
    service apache2 reload

    echo "Site $site_name created and enabled successfully!"
elif [ "$menu_choice" -eq 2 ]; then
    echo "Here is the list of enabled sites:"
    echo "----------------------------------------------"
    apache2ctl -S 2>&1 | grep -v "AH00558" | grep "namevhost" | awk '{print "ServerName: " $4 }'

elif [ "$menu_choice" -eq 3 ]; then
    read -p "Enter the name of the site to remove: " site_name_to_remove

    # Disable site
    a2dissite "$site_name_to_remove"
    service apache2 reload

    # Remove configuration file and log folder
    rm -f "/etc/apache2/sites-available/$site_name_to_remove.conf"
    rm -rf "/var/log/apache2/$site_name_to_remove"

    echo "Site $site_name_to_remove removed successfully!"

else
    echo "Error: Invalid option." >&2
    exit 1

fi

echo "----------------------------------------------"
echo "Script finished."
