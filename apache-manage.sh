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
echo "4. Create SSL certificate and add to Apache"
echo "----------------------------------------------"
read -p "Enter the number of the chosen option: " menu_choice

if [ "$menu_choice" -eq 1 ]; then
    # Read parameters
    read -p "Enter the site name: " site_name
    read -p "Enter the site folder path or reverse proxy address: " site_location
    read -p "Is this configuration a folder (C) or a reverse proxy (R)? [C/R]: " site_type

    # Create log folder
    log_dir="/usr/local/apache2/logs/$site_name"
    mkdir -p "$log_dir"

    # Prepare configuration file
    config_file="/usr/local/apache2/conf/extra/$site_name.conf"

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
    echo "Include conf/extra/$site_name.conf" >> /usr/local/apache2/conf/httpd.conf
    apachectl graceful

    echo "Site $site_name created and enabled successfully!"
elif [ "$menu_choice" -eq 2 ]; then
    echo "Here is the list of enabled sites:"
    echo "----------------------------------------------"
	grep "ServerName" /usr/local/apache2/conf/extra/*.conf | awk -F: '{print $2}'

elif [ "$menu_choice" -eq 3 ]; then
    read -p "Enter the name of the site to remove: " site_name_to_remove

    # Disable site
    sed -i "/Include conf\/extra\/$site_name_to_remove.conf/d" /usr/local/apache2/conf/httpd.conf
    apachectl graceful

    # Remove configuration file and log folder
    rm -f "/usr/local/apache2/conf/extra/$site_name_to_remove.conf"
    rm -rf "/usr/local/apache2/logs/$site_name_to_remove"

    echo "Site $site_name_to_remove removed successfully!"

elif [ "$menu_choice" -eq 4 ]; then
    # Read parameters
    read -p "Enter the domain name: " domain_name
    read -p "Enter the site folder path or reverse proxy address: " site_location
    read -p "Is this configuration a folder (C) or a reverse proxy (R)? [C/R]: " site_type

    # Create log folder
    log_dir="/usr/local/apache2/logs/$domain_name"
    mkdir -p "$log_dir"

    # Prepare configuration file
    config_file="/usr/local/apache2/conf/extra/$domain_name.conf"

    if [ "$site_type" = "C" ] || [ "$site_type" = "c" ]; then
        # Configuration for a folder
        cat >"$config_file" <<EOL
<VirtualHost *:80>
    ServerName $domain_name
    DocumentRoot $site_location

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain_name

    DocumentRoot $site_location

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain_name/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain_name/privkey.pem
</VirtualHost>
EOL
    elif [ "$site_type" = "R" ] || [ "$site_type" = "r" ]; then
        # Configuration for a reverse proxy
        cat >"$config_file" <<EOL
<VirtualHost *:80>
    ServerName $domain_name

    ProxyPass / http://$site_location/
    ProxyPassReverse / http://$site_location/

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain_name

    ProxyPass / http://$site_location/
    ProxyPassReverse / http://$site_location/

    ErrorLog ${log_dir}/error.log
    CustomLog ${log_dir}/access.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain_name/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain_name/privkey.pem
</VirtualHost>
EOL
    else
        echo "Error: Invalid configuration type. Use 'C' for a folder or 'R' for a reverse proxy." >&2
        exit 1
    fi

    # Enable site
	domain_include="Include conf/extra/$domain_name.conf"
	if grep -Fxq "$domain_include" /usr/local/apache2/conf/httpd.conf
	then
		echo "Include for $domain_name already exists in httpd.conf"
	else
		echo "$domain_include" >> /usr/local/apache2/conf/httpd.conf
		
		echo "Include for $domain_name added to httpd.conf"
	fi
	
	apachectl graceful

    # Obtain SSL certificate
    certbot certonly --webroot -w "$site_location" -d "$domain_name" --agree-tos --email ioszxcvbinz@gmail.com

    echo "Site $domain_name created and enabled successfully with SSL!"

else
    echo "Error: Invalid option." >&2
    exit 1

fi

echo "----------------------------------------------"
echo "Script finished."
