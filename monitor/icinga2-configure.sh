#!/bin/bash
#latuannetnam@gmail.com
# Script to configure all feature of Icinga2 toolset: Icinga2, IcingaWeb2, Nagvis, MySQL, PNG4Nagios, Grafana .. in one host
DIR="`pwd`"
HOSTNAME=`hostname --fqdn`

if [[ $EUID -ne 0 ]]; then
 echo "You are not running with root permission. Please chage to root to install required packages"
 exit 1
fi

usage() 
{ 
   echo "Usage: $0 [-c configuration_file]" 1>&2; exit 1; 
}

while getopts ":c:" opt; do
    case "${opt}" in
        c)
            configuration_file=${OPTARG}
            ;;
        *)
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${configuration_file}" ]; then
    usage
    exit 1
fi

echo "Configuration file: ${configuration_file}"
if [ ! -f ${configuration_file} ]; then
    "Configuration not exist"
    exit 1
fi

# Run configuration file to get setttings
. ${configuration_file}

#-----------------------------------------------------#
### Setup Firewall & SELinux
#-----------------------------------------------------#
echo "Configuring security"
# systemctl disable firewalld
# systemctl stop firewalld
# setenforce 0
# sed -i.bak 's/enforcing/disabled/' /etc/selinux/config

if [ ! -z "${SSH_PORT}" ] && [ ${SSH_PORT} != 22 ]; then
    echo "Setup SELinux for SSH"
    semanage port -a -t ssh_port_t -p tcp ${SSH_PORT}
    firewall-cmd --zone=public --add-port=${SSH_PORT}/tcp --permanent
fi




#-----------------------------------------------------#
### Configure MySQL
#-----------------------------------------------------#
if [ ${CONF_MYSQL} == "yes" ]; then
    echo "Configuring MySQL"
    systemctl enable mariadb
    systemctl restart mariadb
    sleep 5
    mysql --version
    mysql_secure_installation
    systemctl restart mariadb
    firewall-cmd --zone=public --add-port=3306/tcp --permanent
    sleep 5

    echo "Provide mysql root password for creating database"
    mysql -u root -p -f -e "CREATE DATABASE ${ICINGA2_DB_NAME}; \
    GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE VIEW, INDEX, EXECUTE ON ${ICINGA2_DB_NAME}.* TO '${ICINGA2_DB_USER}'@localhost IDENTIFIED BY '${ICINGA2_DB_PASSWORD}'; \
    CREATE DATABASE ${ICINGAWEB2_DB_NAME}; \
    GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE VIEW, INDEX, EXECUTE ON ${ICINGAWEB2_DB_NAME}.* TO '${ICINGAWEB2_DB_USER}'@localhost IDENTIFIED BY '${ICINGAWEB2_DB_PASSWORD}'; \
    flush privileges;"
    
    echo "Provide mysql root password for importing ido-mysql data"
    mysql -u root -p ${ICINGA2_DB_NAME} < /usr/share/icinga2-ido-mysql/schema/mysql.sql
    echo "Provide mysql root password for importing icingaweb2 data"
    mysql -u root -p ${ICINGAWEB2_DB_NAME} < /usr/share/doc/icingaweb2/schema/mysql.schema.sql
fi

#-----------------------------------------------------#
### Configure InfluxDB
#-----------------------------------------------------#
if [ ${CONF_INFLUXDB} == "yes" ]; then
    echo "Configuring InfluxDB"
    systemctl enable influxdb
    service influxdb restart
    sleep 5
    echo "Creating influx database"
    influx -execute "CREATE USER admin WITH PASSWORD '${INFLUX_ADMIN_PASSWORD}' WITH ALL PRIVILEGES;"
    influx -execute "CREATE DATABASE ${INFLUX_DB} WITH DURATION 180d;"
    influx -execute "CREATE USER ${INFLUX_USER} WITH PASSWORD '${INFLUX_PASSWORD}';"
    influx -execute "GRANT ALL ON ${INFLUX_DB} to ${INFLUX_USER};"
    echo "Enabling influx authentication"
    sed -i "s:# auth-enabled = false:auth-enabled = true:g" /etc/influxdb/influxdb.conf
    service influxdb restart
    firewall-cmd --zone=public --add-port=8086/tcp --permanent
    firewall-cmd --reload
fi


#-----------------------------------------------------#
### Configure IcingaWeb2
#-----------------------------------------------------#
# if [ ! -z "${CONF_ICINGAWEB2}" ] && [ ${CONF_ICINGAWEB2} == "yes" ]; then
if [ ${CONF_ICINGAWEB2} == "yes" ]; then
    echo "Configuring IcingaWeb2"
    firewall-cmd --zone=public --permanent --add-service=http
    firewall-cmd --zone=public --permanent --add-service=https
    setsebool -P httpd_can_network_connect 1
    setsebool -P httpd_can_network_connect_db 1

    #Remove default for welcome page
    sed -i 's/^/#&/g' /etc/httpd/conf.d/welcome.conf
    # Prevent Apache from displaying files in the "/var/www/html" directory:
    sed -i "s/Options Indexes FollowSymLinks/Options FollowSymLinks/" /etc/httpd/conf/httpd.conf
    #Configure default.conf
    cat > /etc/httpd/conf.d/default.conf <<-END
<VirtualHost *:80>
    ServerAdmin ${HTTPD_SERVERADMIN}
    ServerName ${HTTPD_SERVERNAME}
    ServerAlias ${HTTPD_SERVERNAME}
    DocumentRoot /var/www/html
    ErrorLog /var/log/httpd/error_log
    CustomLog /var/log/httpd/access_log combined
    RewriteEngine on
    RewriteCond %{SERVER_NAME} =${HTTPD_SERVERNAME}
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
    Redirect / /icingaweb2
</VirtualHost>
END
    #Configure /var/www/html/index.html
    cat > /var/www/html/index.html <<-END
    <meta http-equiv="refresh" content="1;url=/icingaweb2" />
END    

    # set timzezone
    sed -i "s:;date.timezone =:date.timezone = Asia/Ho_Chi_Minh:g" /etc/opt/rh/rh-php71/php.ini
    #enable icinga2 modules
    icingacli module enable monitoring
    icingacli module disable setup
    icingacli module disable pnp
    icingacli module disable director
    icingacli module disable businessprocess
    
    # setup IcingaWeb2 resources
    # resources.ini
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db type     "db"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db db       "mysql"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db host     "localhost"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db port     "3306"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db dbname   "${ICINGAWEB2_DB_NAME}"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db username "${ICINGAWEB2_DB_USER}"
    ./ini_set /etc/icingaweb2/resources.ini icingaweb_db password "${ICINGAWEB2_DB_PASSWORD}"

    ./ini_set /etc/icingaweb2/resources.ini icinga_ido type     "db"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido db       "mysql"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido host     "localhost"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido port     "3306"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido dbname   "${ICINGA2_DB_NAME}"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido username "${ICINGA2_DB_USER}"
    ./ini_set /etc/icingaweb2/resources.ini icinga_ido password "${ICINGA2_DB_PASSWORD}"

    # authentication.ini
    ./ini_set /etc/icingaweb2/authentication.ini icingaweb2 backend "db"
    ./ini_set /etc/icingaweb2/authentication.ini icingaweb2 resource "icingaweb_db"

    # config.ini
    ./ini_set /etc/icingaweb2/config.ini global config_backend "db"
    ./ini_set /etc/icingaweb2/config.ini global config_resource "icingaweb_db"
    ./ini_set /etc/icingaweb2/config.ini global module_path "/usr/share/icingaweb2/modules"
    ./ini_set /etc/icingaweb2/config.ini logging  log "file"
    ./ini_set /etc/icingaweb2/config.ini logging  level "WARNING"
    ./ini_set /etc/icingaweb2/config.ini logging  file  "/var/log/icingaweb2/icingaweb2.log"
    ./ini_set /etc/icingaweb2/config.ini cookie  path "/"
    # ./ini_set /etc/icingaweb2/config.ini global  ""
    # ./ini_set /etc/icingaweb2/config.ini global  ""

    # groups.ini
    ./ini_set /etc/icingaweb2/groups.ini icingaweb2 backend "db"
    ./ini_set /etc/icingaweb2/groups.ini icingaweb2 resource "icingaweb_db"

    # Write Icingaweb2 user and password to installation
    ./ini_set /etc/icingaweb2/roles.ini Administrators users "admin"
    ./ini_set /etc/icingaweb2/roles.ini Administrators permissions "*"
    ./ini_set /etc/icingaweb2/roles.ini Administrators groups "Administrators"

    ICINGAWEB2_ADMIN_PASS_HASH=$(openssl passwd -1 "${ICINGAWEB2_ADMIN_PASS}")
    echo "ICINGAWEB2_ADMIN_PASS_HASH=${ICINGAWEB2_ADMIN_PASS_HASH}"
    echo "Provive mysql root password for creating icingaweb2 admin user"
    mysql -u root -p ${ICINGAWEB2_DB_NAME} -e "INSERT IGNORE INTO icingaweb_user (name, active, password_hash) VALUES ('admin', 1, '${ICINGAWEB2_ADMIN_PASS_HASH}');"

    # setup IcingaWeb2 monitoring module
    # backends.ini
    mkdir -p /etc/icingaweb2/modules/monitoring
    ./ini_set /etc/icingaweb2/modules/monitoring/backends.ini icinga type "ido"
    ./ini_set /etc/icingaweb2/modules/monitoring/backends.ini icinga resource "icinga_ido"
    
    # commandtransports.ini
    ./ini_set /etc/icingaweb2/modules/monitoring/commandtransports.ini ${ICINGAWEB2_TRANSPORT_SESSION}   transport "api"
    ./ini_set /etc/icingaweb2/modules/monitoring/commandtransports.ini ${ICINGAWEB2_TRANSPORT_SESSION}   host      "${ICINGAWEB2_TRANSPORT_HOST}"  
    ./ini_set /etc/icingaweb2/modules/monitoring/commandtransports.ini ${ICINGAWEB2_TRANSPORT_SESSION}   port       "5665"
    ./ini_set /etc/icingaweb2/modules/monitoring/commandtransports.ini ${ICINGAWEB2_TRANSPORT_SESSION}   username   "${ICINGAWEB2_TRANSPORT_USER}" 
    ./ini_set /etc/icingaweb2/modules/monitoring/commandtransports.ini ${ICINGAWEB2_TRANSPORT_SESSION}   password   "${ICINGAWEB2_TRANSPORT_PASSWORD}"   
    
    # config.ini
    ./ini_set /etc/icingaweb2/modules/monitoring/config.ini security    protected_customvars    "*pw*,*pass*,*community*"

    # set permission
    chown -R apache.icingaweb2 /etc/icingaweb2
    
    # restart services
    systemctl enable httpd.service
    systemctl restart httpd.service
    systemctl enable rh-php71-php-fpm.service
    systemctl restart rh-php71-php-fpm.service
fi

#-----------------------------------------------------#
### Configure Grafana
#-----------------------------------------------------#

if [ ${CONF_GRAFANA} == "yes" ]; then
    echo "Configuring Grafana"
    systemctl enable grafana-server
    service grafana-server restart
    sleep 5
    echo "Creating API key"
    GRAFANA_API_KEY=`curl -s --header "Content-Type: application/json" \
        --request POST \
        --data '{"name":"monitor","role":"Viewer"}' \
        http://admin:admin@localhost:3000/api/auth/keys | jq '.key'`
    echo "GRAFANA_API_KEY=${GRAFANA_API_KEY}"

    echo "Creating datasource"
    curl -s --request POST \
        http://admin:admin@localhost:3000/api/datasources \
        --header "Content-Type: application/json" \
        --data @- << EOF
{
 "name": "$GRAFANA_DS",
 "type": "influxdb",
 "url": "http://localhost:8086",
 "access": "proxy",
 "database": "$INFLUX_DB",
 "user": "$INFLUX_USER", 
 "password": "$INFLUX_PASSWORD"
}
EOF

    echo " "
    echo "Creating dashboards"

    # curl  -s -u admin 'https://mon-web.netnam.vn/grafana/api/dashboards/uid/R4cMn3tik' | jq '.' > icinga2-default.json
    sed -i "s:GRAFANA_DS:$GRAFANA_DS:g" grafana/icinga2-default.json
    GRAFANA_DB_ICINGA2_DEFAULT=`curl -s --request POST \
  http://admin:admin@localhost:3000/api/dashboards/db \
  --header "Content-Type: application/json" \
  --data @grafana/icinga2-default.json | jq '.uid'`
    echo "GRAFANA_DB_ICINGA2_DEFAULT=${GRAFANA_DB_ICINGA2_DEFAULT}"

    # curl  -s -u admin 'https://mon-web.netnam.vn/grafana/api/dashboards/uid/xpkKQ70iz' | jq '.' > icinga2-hostalive.json
    sed -i "s:GRAFANA_DS:$GRAFANA_DS:g" grafana/icinga2-hostalive.json
    GRAFANA_DB_ICINGA2_HOSTALIVE=`curl -s --request POST \
  http://admin:admin@localhost:3000/api/dashboards/db \
  --header "Content-Type: application/json" \
  --data @grafana/icinga2-hostalive.json | jq '.uid'`
    echo "GRAFANA_DB_ICINGA2_HOSTALIVE=${GRAFANA_DB_ICINGA2_HOSTALIVE}"

    # curl  -s -u admin 'https://mon-web.netnam.vn/grafana/api/dashboards/uid/-fhSWxxmz' | jq '.' > icinga2-interface-health-single.json
    sed -i "s:GRAFANA_DS:$GRAFANA_DS:g" grafana/icinga2-interface-health-single.json
    GRAFANA_DB_ICINGA2_INTERFACE_HEALTH=`curl -s --request POST \
  http://admin:admin@localhost:3000/api/dashboards/db \
  --header "Content-Type: application/json" \
  --data @grafana/icinga2-interface-health-single.json | jq '.uid'`
    echo "GRAFANA_DB_ICINGA2_INTERFACE_HEALTH=${GRAFANA_DB_ICINGA2_INTERFACE_HEALTH}"

    echo "Fine tunning Grafana"
    sed -i "s:;http_addr =:http_addr = 127.0.0.1:g" /etc/grafana/grafana.ini
    sed -i "s:;enable_gzip = false:enable_gzip = true:g" /etc/grafana/grafana.ini
    sed -i "s:;domain = localhost:domain = $HTTPD_SERVERNAME:g" /etc/grafana/grafana.ini
    sed -i "s:;enforce_domain = false:enforce_domain = true:g" /etc/grafana/grafana.ini
    sed -i "s|;root_url = http://localhost:3000|root_url = http://$HTTPD_SERVERNAME/grafana|g" /etc/grafana/grafana.ini|
    service grafana-server restart
    
fi

#-----------------------------------------------------#
### Configure IcingaWeb2 Grafana
#-----------------------------------------------------#
if [ ${CONF_ICINGAWEB2_GRAFANA} == "yes" ]; then
    echo "Configuring IcingaWeb2 Grafana"
    #Temporarily for grafana
    # firewall-cmd --zone=public --add-port=3000/tcp
    icingacli module enable grafana
    mkdir -p /etc/icingaweb2/modules/grafana
    echo "Creating config.ini"
    cat > /etc/icingaweb2/modules/grafana/config.ini <<-END
[grafana]
version = "1"
host = "${HTTPD_SERVERNAME}/grafana"
protocol = "http"
timerangeAll = "1w/w"
defaultdashboard = "icinga2-default"
defaultdashboarduid = ${GRAFANA_DB_ICINGA2_DEFAULT}
defaultdashboardpanelid = "1"
defaultorgid = "1"
shadows = "0"
theme = "light"
datasource = "influxdb"
accessmode = "indirectproxy"
debug = "0"
authentication = "token"
height = "350"
width = "800"
enableLink = "yes"
ssl_verifypeer = "1"
ssl_verifyhost = "1"
indirectproxyrefresh = "yes"
apitoken = ${GRAFANA_API_KEY}
END

echo "Creating graphs.ini"
cat > /etc/icingaweb2/modules/grafana/graphs.ini <<-END
[hostalive]
dashboard = "icinga2-hostalive"
panelId = "1"
orgId = ""
repeatable = "no"
dashboarduid = ${GRAFANA_DB_ICINGA2_HOSTALIVE}

[if-health]
dashboard = "icinga2-interface-health-single"
panelId = "2,3,4,5,6"
orgId = "1"
repeatable = "no"
dashboarduid = ${GRAFANA_DB_ICINGA2_INTERFACE_HEALTH}
END

fi

#-----------------------------------------------------#
### Configure Nagvis
#-----------------------------------------------------#
if [ ${CONF_NAGVIS} == "yes" ]; then
    echo "Configuring Nagvis"
fi    

#-----------------------------------------------------#
### Configure IcingaWeb2 Nagvis
#-----------------------------------------------------#
if [ ${CONF_ICINGAWEB2_NAGVIS} == "yes" ]; then
    echo "Configuring IcingaWeb2 Nagvis"
fi    

#-----------------------------------------------------#
### Configure Icinga2
#-----------------------------------------------------#
if [ ${CONF_ICINGA2} == "yes" ]; then
    echo "Configuring Icinga2"
    systemctl enable icinga2
    firewall-cmd --zone=public --add-port=5665/tcp --permanent    
    icinga2 feature enable api checker compatlog ido-mysql influxdb livestatus mainlog
    # configure IDO-MySQL
    cat > /etc/icinga2/features-enabled/ido-mysql.conf <<-END
object IdoMysqlConnection "ido-mysql" {
  user = "${ICINGA2_DB_USER}",
  password = "${ICINGA2_DB_PASSWORD}",
  host = "localhost",
  database = "${ICINGA2_DB_NAME}"
  cleanup = {
    downtimehistory_age = 48h
    contactnotifications_age = 60d
    statehistory_age = 180d
    notifications_age = 60d
  }
}
END
    
    # configure InfluxDB
    cat > /etc/icinga2/features-enabled/influxdb.conf <<-END
library "perfdata"
object InfluxdbWriter "influxdb" {
  host = "127.0.0.1"
  port = 8086
  database = "${INFLUX_DB}"
  username = "${INFLUX_USER}"
  password = "${INFLUX_PASSWORD}"
  flush_threshold = 1024
  flush_interval = 10s
  enable_send_thresholds = true
  enable_send_metadata = true

  host_template = {
    measurement = "$host.check_command$"
    tags = {
      hostname = "$host.name$"
      zone = "$host.zone$"	
      server_type = "$host.vars.server_types$"	
    }
  }

  service_template = {
    measurement = "$service.check_command$"
    tags = {
      hostname = "$host.name$"
      service = "$service.name$"
      zone = "$host.zone$"
      server_type = "$host.vars.server_types$"
      host_group = "$host.groups$"		
    }
  }
}
END
    
    # configure livestatus
    cat > /etc/icinga2/features-enabled/livestatus.conf <<-END
object LivestatusListener "livestatus" { }
object LivestatusListener "livestatus-tcp" {
  socket_type = "tcp"
  bind_host = "127.0.0.1"
  bind_port = "6558"
  }
END
    icinga2 node wizard
    systemctl restart icinga2
fi

# Configure security
firewall-cmd --reload
firewall-cmd --list-port
echo "Done!"