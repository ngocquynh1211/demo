#!/bin/bash
#latuannetnam@gmail.com
# Script to install all feature of Icinga2 toolset: Icinga2, IcingaWeb2, Nagvis, MySQL, PNG4Nagios, InfluxDB, Grafana, ElasticSearch in one host
DIR="/root"
HOSTNAME=`hostname --fqdn`
INSTALL_DIR="$DIR/monitor-packages"

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


echo "Checking Linux platform"
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/centos-release ]; then
    OS="centos"
    VER=$(rpm -q --queryformat '%{VERSION}' centos-release)    
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
else
    echo "Could not determine distribution. Exit"
    exit 1
fi

echo "OS: $OS. Version: $VER"
if [ $OS == "centos" ]; then
   if [ $VER != "7" ]; then
     echo "Not support distribution. Exiting!"
     exit 1
   fi    
else
    echo "Not support distribution. Exiting!"
    exit 1    
fi


#-----------------------------------------------------#
### Install pre-components
#-----------------------------------------------------#
echo "Installing pre-requisite components"
PLUGIN_DIR="/usr/lib64/nagios/plugins"
ICINGA2_USER="icinga"
yum -y install epel-release 
yum -y update
yum -y install sudo wget unzip mc net-tools git curl nano which ntp jq dos2unix policycoreutils-python mailx psmisc nfs-utils net-snmp-python
yum install -y "perl(DBD::mysql)"    


# MariaDB repo
echo "Installing MariaDB repo"
# curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
cat > /etc/yum.repos.d/MariaDB.repo <<-END
# MariaDB 10.3 CentOS repository list - created 2018-08-26 01:08 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.4/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
END



# auto update packages
# sed -i 's:apply_updates = no:apply_updates = yes:g' /etc/yum/yum-cron.conf
# sed -i "s|^email_to = root|email_to = ${EMAIL}|" /etc/yum/yum-cron.conf
# echo "Setting yum-cron update policy"
# sed -i 's|^update_cmd = default|update_cmd = minimal|' /etc/yum/yum-cron.conf
# sed -i 's|^update_messages = no|update_messages = yes|' /etc/yum/yum-cron.conf
# sed -i 's|^download_updates = no|download_updates = yes|' /etc/yum/yum-cron.conf
# sed -i 's|^apply_updates = no|apply_updates = yes|' /etc/yum/yum-cron.conf
# sed -i 's|^emit_via = stdio|emit_via = email|' /etc/yum/yum-cron.conf

# sed -i "s|^email_to = root|email_to = ${EMAIL}|" /etc/yum/yum-cron-hourly.conf
# sed -i 's|^update_cmd = default|update_cmd = security|' /etc/yum/yum-cron-hourly.conf
# sed -i 's|^update_messages = no|update_messages = yes|' /etc/yum/yum-cron-hourly.conf
# sed -i 's|^download_updates = no|download_updates = yes|' /etc/yum/yum-cron-hourly.conf
# sed -i 's|^apply_updates = no|apply_updates = yes|' /etc/yum/yum-cron-hourly.conf
# sed -i 's|^emit_via = stdio|emit_via = email|' /etc/yum/yum-cron-hourly.conf   
# systemctl enable yum-cron
# service yum-cron start
# enable time sync
systemctl enable ntpd
# service ntpd start


if [ ! -z ${CONF_ICINGA2+x} ] && [ ${CONF_ICINGA2} == "yes" ]; then
    echo "Installing Icinga2 pre-components"
    ## Perl modules
    yum -y install perl-Net-SNMP \
                perl net-snmp-perl \
                perl-XML-LibXML \
                perl-JSON perl-libwww-perl \
                perl-XML-XPath perl-Net-Telnet \
                perl-Net-DNS perl-DBI perl-DBD-MySQL \
                perl-DBD-Pg perl-CPAN
    yum install -y https://packages.icinga.com/epel/icinga-rpm-release-7-latest.noarch.rpm	
    yum group install -y "Development Tools"
    # Additional lib for VMware
    yum install -y  e2fsprogs e2fsprogs-devel libuuid-devel openssl-devel perl-devel glibc.i686 zlib.i686 perl-XML-LibXML libncurses.so.5 perl-Crypt-SSLeay

    # Install CPAN modules
    echo "Installing CPAN modules"
    # export PERL_MM_USE_DEFAULT=1             
    # cpan CPAN Log::Log4perl
    cpan App::cpanminus
    cpanm --notest IO::Socket::SSL Pod::Find Sys::Statistics::Linux Readonly Nagios::Monitoring::Plugin Monitoring::Plugin JSON::XS
    cpanm --notest Net::LDAP Data::Dump WWW::Selenium::Util Test::Harness::Straps Shell LWPx::TimedHTTP  WWW::Mechanize::Timed 
    cpanm --notest Proc::ProcessTable inc::Module::Install SMS::AQL Net::Amazon::EC2 Net::Amazon::S3
    # cpanm Nagios::Monitoring::Plugin::Getopt Readonly

    #Install Java
    if [ ! -f "/usr/bin/java" ]; then
        echo "Installing Oracle Java 12"	
        cd ${INSTALL_DIR}/java
        yum localinstall -y jdk-*
    fi   
    #-----------------------------------------------------#
    ### Install icinga2
    #-----------------------------------------------------#
    echo "Installing Icinga2"
    yum install -y icinga2 nagios-plugins-all nagios-plugins-nrpe
    # yum install -y icinga2-ido-mysql mariadb
    #-----------------------------------------------------#
    ### Install icinga2 plugins all modes
    #-----------------------------------------------------#
    echo "Installing Icinga2 plugins"

    ### Installing Centreon plugin
    if [ ! -d "${PLUGIN_DIR}/thirdparty/centreon-plugins" ]; then
        echo "Installing centrons plugins"
        mkdir -p ${PLUGIN_DIR}/thirdparty
        cd ${PLUGIN_DIR}/thirdparty
        # wget https://github.com/centreon/centreon-plugins/archive/20180928.tar.gz
        # wget https://github.com/centreon/centreon-plugins/archive/20190111.tar.gz
        # tar -zvxf 20190111.tar.gz
        cp ${INSTALL_DIR}/thirdparty/centreon-plugins-20190111.tar.gz ./
        tar -zvxf centreon-plugins-20190111.tar.gz
        mv centreon-plugins-20190111 centreon-plugins
        cd centreon-plugins
        chmod +x centreon_plugins.pl
        mkdir -p /var/lib/centreon/centplugins
        chown -R ${ICINGA2_USER}.${ICINGA2_USER} /var/lib/centreon/
    fi

    # Install check_wmi_plus
    if [ ! -f "${PLUGIN_DIR}/check_wmi_plus.pl" ]; then
        echo "Installing check_wmi_plus"
        cpanm --notest Config::IniFiles Getopt::Long DateTime Number::Format Data::Dumper Scalar::Util Storable
        rpm -Uvh http://www6.atomicorp.com/channels/atomic/centos/7/x86_64/RPMS/atomic-release-1.0-21.el7.art.noarch.rpm
        yum install -y wmi
        cd ${PLUGIN_DIR}
        # wget http://edcint.co.nz/checkwmiplus/sites/default/files/check_wmi_plus.v1.63.tar.gz
        cp ${INSTALL_DIR}/thirdparty/check_wmi_plus.v1.64.tar.gz ./
        tar -zvxf check_wmi_plus.v1.64.tar.gz		
        chmod +x check_wmi_plus.pl
        # copy configuration
        if [ ! -d "/etc/check_wmi_plus" ]; then
            cp -r etc/check_wmi_plus /etc
            cp /etc/check_wmi_plus/check_wmi_plus.conf.sample /etc/check_wmi_plus/check_wmi_plus.conf
            chown -R ${ICINGA2_USER}.${ICINGA2_USER} /etc/check_wmi_plus
            sed -i 's|^$base_dir=|$base_dir="/usr/lib64/nagios/plugins"; #|' /etc/check_wmi_plus/check_wmi_plus.conf
            # echo "Please set The variable '$base_dir' in /etc/check_wmi_plus/check_wmi_plus.conf to /usr/lib64/nagios/plugins"		
        fi 
    fi # End of check_wmi_plus

    # check_nwc_health plugin
    if [ ! -f "${PLUGIN_DIR}/check_nwc_health" ]; then
        echo "Installing check_nwc_health"
        cd ${PLUGIN_DIR}
        # wget https://labs.consol.de/assets/downloads/nagios/check_nwc_health-7.2.0.2.tar.gz
        cp ${INSTALL_DIR}/thirdparty/check_nwc_health-7.10.0.4.1.tar.gz ./
        tar -zvxf check_nwc_health-7.10.0.4.1.tar.gz
        cd check_nwc_health-7.10.0.4.1
        ./configure
        make
        make check
        cp plugins-scripts/check_nwc_health ../
        cd ../
        chmod +x check_nwc_health
    fi # End of check_nwc_health

    # VMware SDK
    if [ ! -f "/usr/lib/vmware-vcli/apps/vm/guestinfo.pl" ]; then
        echo "Installing VMWare SDK"
        cpanm --notest UUID Time::Duration File::Basename HTTP::Date Getopt::Long Time::HiRes IO::Compress::Zlib::Extra
        cpanm --notest Time::Piece Archive::Zip Text::Template Path::Class LWP::Protocol::https  Net::INET6Glue
        cpanm --notest IO::Socket::INET6
        # wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1m4a1iuGQFzgfN5nOYUg4Zb8bv2qT65Ow' -O VMware-vSphere-Perl-SDK-6.7.0-8156551.x86_64.tar.gz
        cd ${INSTALL_DIR}
        tar -zvxf vmware/VMware-vSphere-Perl-SDK-6.7.0-8156551.x86_64.tar.gz
        cd vmware-vsphere-cli-distrib
        ./vmware-install.pl
        cd /usr/share/perl5/VMware
        cp VICommon.pm VICommon.pm.org
        cp -f ${INSTALL_DIR}/vmware/VICommon.pm ./  
    fi     

    # check_vmware plugin
    if [ ! -f "${PLUGIN_DIR}/check_vmware_esx" ]; then
        echo "Installing check_vmware_esx. Please make sure Vsphere SDK installed and worked before!"
        cd ${PLUGIN_DIR}
        git clone https://github.com/BaldMansMojo/check_vmware_esx.git check_vmware_esx.d
        cd check_vmware_esx.d
        make
        cp check_vmware_esx ../
    fi # End of install check_vmware

    # check_jmx plugin
    if [ ! -d "${PLUGIN_DIR}/thirdparty/nagios-jmx-plugin" ]; then
        echo "Installing check_jmx"
        cd ${PLUGIN_DIR}/thirdparty
        # wget https://snippets.syabru.ch/nagios-jmx-plugin/download/nagios-jmx-plugin.zip
        cp ${INSTALL_DIR}/thirdparty/nagios-jmx-plugin.zip ./
        unzip nagios-jmx-plugin.zip
        mv nagios-jmx-plugin-1.2.3 nagios-jmx-plugin
        cd nagios-jmx-plugin
        cp -f ${INSTALL_DIR}/check_jmx/check_jmx ./
        cp -f ${INSTALL_DIR}/check_jmx/jboss-client-eap-7.2.jar ./
        dos2unix check_jmx
        chmod +x check_jmx
    fi

    ### Installing monitor-plugins
    if [ ! -d "${PLUGIN_DIR}/thirdparty/monitor-plugins" ]; then
        echo "Installing monitor-plugins"
        cd ${PLUGIN_DIR}/thirdparty
        git clone https://monitor:6BVvApGryKPHCECSxQzn@tsd-repo.netnam.vn/monitoring/monitor-plugins.git
        echo "${ICINGA2_USER} ALL=(root) NOPASSWD: ${PLUGIN_DIR}/thirdparty/monitor-plugins/plugin-update.sh" | EDITOR='tee -a' visudo -f /etc/sudoers.d/icinga2
        echo "${ICINGA2_USER} ALL=(root) NOPASSWD: ${PLUGIN_DIR}/thirdparty/monitor-plugins/icinga2-validation.sh" | EDITOR='tee -a' visudo -f /etc/sudoers.d/icinga2
    fi

    # check_yum_updates
    if [ ! -f "${PLUGIN_DIR}/check_updates" ]; then
        echo "Installing check_updates"
        cpanm --notest Readonly Monitoring::Plugin
        cd ${PLUGIN_DIR}
        # wget https://github.com/matteocorti/check_updates/releases/download/v1.6.23/check_updates-1.6.23.tar.gz
        cp ${INSTALL_DIR}/thirdparty/check_updates-1.6.23.tar.gz ./
        tar -zvxf check_updates-1.6.23.tar.gz
        cd check_updates-1.6.23
        perl Makefile.PL
        make
        cp blib/script/check_updates ../
        cd ..
        chmod +x check_updates
    fi

    # proxysql-nagios
    if  [ ! -d "${PLUGIN_DIR}/thirdparty/proxysql-nagios" ]; then
        echo "Installing proxysql-nagios"
        cd ${PLUGIN_DIR}/thirdparty
        git clone https://github.com/sysown/proxysql-nagios.git
        # Install dependencies
        if [ $OS == "ubuntu" ]; then
            apt install -y python-mysqldb
        elif [ $OS == "centos" ]; then
            yum install -y MySQL-python
        fi
    fi

    # Check Oracle heatlh
    if [ ! -f "${PLUGIN_DIR}/check_oracle_health" ]; then
        echo "Installing perl-DBD-Oracle"
        cd ${INSTALL_DIR}/oracle
        yum localinstall -y oracle* --nogpgcheck
        # Export environtment variables
        export PATH=$PATH:/usr/lib/oracle/12.2/client64/bin
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/oracle/12.2/client64/lib
        export ORACLE_HOME=/usr/lib/oracle/12.2/client64
        export TNS_ADMIN=$ORACLE_HOME/network/admin
        cpanm --notest DBD::Oracle
        echo "Installing check_oracle_health"
        cd ${PLUGIN_DIR}
        # wget https://labs.consol.de/assets/downloads/nagios/check_oracle_health-3.2.tar.gz
        cp ${INSTALL_DIR}/thirdparty/check_oracle_health-3.2.tar.gz ./
        tar -zvxf check_oracle_health-3.2.tar.gz
        cd check_oracle_health-3.2
        ./configure
        make
        make check
        cp plugins-scripts/check_oracle_health ../
        cd ../
        chmod +x check_oracle_health
        # Setup default environtment variable
        cat >> /etc/sysconfig/icinga2 <<-END
PATH=$PATH:/usr/lib/oracle/12.2/client64/bin
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/oracle/12.2/client64/lib
ORACLE_HOME=/usr/lib/oracle/12.2/client64
TNS_ADMIN=$ORACLE_HOME/network/admin
END
    fi # End of Check Oracle heatlh

    # check_mssql_health
    if [ ! -f "${PLUGIN_DIR}/check_mssql_health" ]; then
        echo "Installing DBD::Sybase"
        cd /root
        wget http://yum.centreon.com/standard/dev/el7/stable/x86_64/RPMS/perl-DBD-Sybase-1.15-2.el7.centos.x86_64.rpm
        yum localinstall -y perl-DBD-Sybase*
        echo "Install check_mssql_health"
        cd ${PLUGIN_DIR}
        wget https://labs.consol.de/assets/downloads/nagios/check_mssql_health-2.6.4.15.tar.gz
        tar -zvxf check_mssql_health-2.6.4.15.tar.gz
        cd check_mssql_health-2.6.4.15
        ./configure --with-nagios-user=${ICINGA2_USER} --with-nagios-group=${ICINGA2_USER}
        make
        cp plugins-scripts/check_mssql_health ../
    fi  # End of check_mssql_healthatuan

    #-----------------------------------------------------#
    # copy local perl modules to global path
    #-----------------------------------------------------#
    echo "Copy local perl modules to global path"
    mkdir -p /usr/local/share/perl5
    cp -nru ~/perl5/lib/perl5/*  /usr/local/share/perl5/
    cp -nru ~/perl5/lib/perl5/x86_64-linux-thread-multi/* /usr/local/share/perl5/

    #-----------------------------------------------------#
    # echo "Setup icinga2 startup"
    #-----------------------------------------------------#
    systemctl enable icinga2
    #-----------------------------------------------------#

    if [ ! -z ${CONF_ICINGA2_MODE+x} ] && [ ${CONF_ICINGA2_MODE} == "proxy" ]; then
        echo "Installing IDO-MySQL for master/proxy mode"
        yum install -y icinga2-ido-mysql MariaDB-client
    fi

    # Test plugins
    #-----------------------------------------------------#
    echo "Test plugins"
    echo "Test Java"
    java -version
    echo "Test centreon"
    ${PLUGIN_DIR}/thirdparty/centreon-plugins/centreon_plugins.pl --plugin os::linux::local::plugin --mode memory
    echo "Test check_nwc"
    ${PLUGIN_DIR}/check_nwc_health -v
    echo "Test check_vmware"
    ${PLUGIN_DIR}/check_vmware_esx -H 127.0.0.1
    echo "Test check_jmx"
    ${PLUGIN_DIR}/thirdparty/nagios-jmx-plugin/check_jmx
    echo "Test check_update"
    ${PLUGIN_DIR}/check_updates
    echo "Test proxysql-nagios"
    ${PLUGIN_DIR}/thirdparty/proxysql-nagios/proxysql-nagios
    echo "Test check_oracle"
    ${PLUGIN_DIR}/check_oracle_health -v
fi # END of if [ ${CONF_ICINGA2} == "yes" ]; then    

if [ ! -z ${CONF_MYSQL+x} ] && [ ${CONF_MYSQL} == "yes" ]; then
    echo "Installing MySQL"
    #-----------------------------------------------------#
    ### Install MySQL
    #-----------------------------------------------------#
    yum install -y MariaDB-server MariaDB-client MariaDB-common rsync lsof MariaDB-backup
    # Install database for icinga2 and icingaweb2
    yum install -y centos-release-scl 
    yum install -y icinga2-ido-mysql icingaweb2 icingaweb2-selinux sclo-php71-php-pecl-imagick
    systemctl enable mariadb
    # Set SELinux policy for Galera
    # semodule -i galera.pp
    #  Firewall setting
    firewall-cmd --zone=public --add-service=mysql --permanent
    firewall-cmd --zone=public --add-port=3306/tcp --permanent
    firewall-cmd --zone=public --add-port=4567/tcp --permanent
    firewall-cmd --zone=public --add-port=4567/udp --permanent
    firewall-cmd --zone=public --add-port=4444/tcp --permanent
    firewall-cmd --reload
fi    

if [ ! -z ${CONF_ICINGAWEB2+x} ] && [ ${CONF_ICINGAWEB2} == "yes" ]; then
    echo "Installing IcingaWeb2"
    #-----------------------------------------------------#
    ### Install icingaWeb2
    #-----------------------------------------------------#
    yum install -y httpd mod_ssl python-certbot-apache
    yum install -y centos-release-scl
    yum install -y icingaweb2 icingacli icingaweb2-selinux sclo-php71-php-pecl-imagick  MariaDB-client
    #-----------------------------------------------------#
    ### Install icingaWeb2 modules
    #-----------------------------------------------------#

    # Business process
    if [ ! -d "/usr/share/icingaweb2/modules/businessprocess" ]; then
        echo "Installing icingaWeb2 businessprocess"
        cd /usr/share/icingaweb2/modules
        git clone https://github.com/Icinga/icingaweb2-module-businessprocess.git businessprocess
        # icingacli module enable businessprocess
    fi

    #Director 
    if [ ! -d "/usr/share/icingaweb2/modules/director" ]; then
        echo "Installing icingaWeb2 Director"
        cd /usr/share/icingaweb2/modules
        git clone https://github.com/Icinga/icingaweb2-module-director.git director
        # icingacli module enable director
    fi

    # Nagivs
    if [ ! -d "/usr/share/icingaweb2/modules/nagvis" ]; then
        echo "Installing icingaWeb2 nagvis"
        cd /usr/share/icingaweb2/modules
        git clone https://github.com/Icinga/icingaweb2-module-nagvis.git nagvis
        # icingacli module enable nagvis
    fi

    # Grafana
    if [ ! -d "/usr/share/icingaweb2/modules/grafana" ]; then
        echo "Installing icingaWeb2 grafana"
        cd /usr/share/icingaweb2/modules
        git clone https://github.com/Mikesch-mp/icingaweb2-module-grafana.git grafana
        # icingacli module enable grafana
    fi
    # Elasticsearch
    if [ ! -d "/usr/share/icingaweb2/modules/elasticsearch" ]; then
        echo "Installing icingaWeb2 elasticsearch"
        cd /usr/share/icingaweb2/modules
        git clone https://github.com/icinga/icingaweb2-module-elasticsearch.git elasticsearch
        # icingacli module enable elasticsearch
    fi
fi    

if [ ! -z ${CONF_GRAFANA+x} ] && [ ${CONF_GRAFANA} == "yes" ]; then
    #-----------------------------------------------------#
    ### Install Grafana
    #-----------------------------------------------------#
    echo "Installing Grafana"
    cat > /etc/yum.repos.d/grafana.repo <<-END
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
END
        yum install -y grafana
        systemctl enable grafana-server
fi  


if [ ! -z ${CONF_INFLUXDB+x} ] && [ ${CONF_INFLUXDB} == "yes" ]; then
    echo "Installing InfluxDB"
     #-----------------------------------------------------#
    ### Install InfluxDB
    #-----------------------------------------------------#
    cd ${INSTALL_DIR}
    wget https://dl.influxdata.com/influxdb/releases/influxdb-1.7.7.x86_64.rpm
    yum localinstall -y influxdb-*
    systemctl enable influxdb
fi  

if [ ! -z ${CONF_ELASTICSEARCH+x} ] && [ ${CONF_ELASTICSEARCH} == "yes" ]; then
    #-----------------------------------------------------#
    ### Install ELASTICSEARCH
    #-----------------------------------------------------#
    echo "Installing Elasticsearch"
    yum -y install apr-util-mysql
    rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
    cat > /etc/yum.repos.d/elasticsearch.repo <<-END
[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
END

    echo "Installing Curator"
    cat > /etc/yum.repos.d/curator.repo <<-END
[curator-5]
name=CentOS/RHEL 7 repository for Elasticsearch Curator 5.x packages
baseurl=https://packages.elastic.co/curator/5/centos/7
gpgcheck=1
gpgkey=https://packages.elastic.co/GPG-KEY-elasticsearch
enabled=1
END

    yum install -y elasticsearch elasticsearch-curator
    systemctl enable elasticsearch
    # Install search-guard plugin
    # /usr/share/elasticsearch/bin/elasticsearch-plugin install -b com.floragunn:search-guard-6:6.6.1-24.1
    # cd /usr/share/elasticsearch/plugins/search-guard-6/
    # wget https://search.maven.org/remotecontent?filepath=com/floragunn/search-guard-tlstool/1.6/search-guard-tlstool-1.6.tar.gz  -O search-guard-tlstool-1.6.tar.gz
    # tar -zvxf search-guard-tlstool*.tar.gz
fi 

if [ ! -z ${CONF_KIBANA+x} ] && [ ${CONF_KIBANA} == "yes" ]; then
    #-----------------------------------------------------#
    ### Install KIBANA
    #-----------------------------------------------------#
    echo "Installing Elasticsearch"
    yum -y install apr-util-mysql
    rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
    cat > /etc/yum.repos.d/kibana.repo <<-END
[kibana-7.x]
name=Kibana repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
END

    yum install -y elasticsearch kibana
    systemctl enable kibana
   
fi

if [ ! -z ${CONF_HAPROXY+x} ] && [ ${CONF_HAPROXY} == "yes" ]; then
    echo "Installing HAPROXY"
     #-----------------------------------------------------#
    ### Install HAPROXY
    #-----------------------------------------------------#
    # https://pario.no/2018/07/17/install-haproxy-1-8-on-centos-7/
    yum install -y centos-release-scl 
    yum install -y rh-haproxy18-haproxy rh-haproxy18-haproxy-syspaths
    systemctl enable rh-haproxy18-haproxy
    # yum -y install haproxy
    # systemctl enable haproxy
fi  

if [ ! -z ${CONF_MAXSCALE+x} ] && [ ${CONF_MAXSCALE} == "yes" ]; then
    echo "Installing MAXSCALE"
     #-----------------------------------------------------#
    ### Install MAXSCALE
    #-----------------------------------------------------#
    # wget https://downloads.mariadb.com/MaxScale/2.3.3/centos/7/x86_64/maxscale-2.3.3-1.centos.7.x86_64.rpm
    # yum localinstall -y maxscale-*    
    cat > /etc/yum.repos.d/maxscale.repo <<-END
[maxscale]
name=maxscale
baseurl=https://downloads.mariadb.com/files/MaxScale/latest/centos/7/x86_64
gpgkey=https://downloads.mariadb.com/software/MaxScale/MaxScale-GPG-KEY.public
enabled=1
gpgcheck=true
END
    yum install -y maxscale  MariaDB-client
    systemctl enable maxscale
fi  


if [ ! -z ${CONF_PROXYSQL+x} ] && [ ${CONF_PROXYSQL} == "yes" ]; then
    echo "Installing PROXYSQL"
    cd ${INSTALL_DIR}
     #-----------------------------------------------------#
    ### Install PROXYSQL
    #-----------------------------------------------------#
    wget https://github.com/sysown/proxysql/releases/download/v2.0.1/proxysql-2.0.1-1-centos7.x86_64.rpm
    yum localinstall -y proxysql-*
    yum install -y  MariaDB-client
    systemctl enable proxysql
fi  

if [ ! -z ${CONF_INFLUXRELAY+x} ] && [ ${CONF_INFLUXRELAY} == "yes" ]; then
    echo "Installing INFLUXRELAY"
     #-----------------------------------------------------#
    ### Install INFLUXRELAY
    #-----------------------------------------------------#
    GOPATH=/usr/local/go
    if [ ! -d "${GOPATH}" ]; then
        echo "Installing go"
        cd ${INSTALL_DIR}
        # Installing go
        wget https://dl.google.com/go/go1.11.5.linux-amd64.tar.gz
        tar -C /usr/local -xzf  go1.11.5.linux-amd64.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
        chmod +x  /etc/profile.d/go.sh
        /etc/profile.d/go.sh
    fi
    # Installing InfluxDB Relay
    echo "Download and build influx-relay"
    ${GOPATH}/bin/go get -u github.com/vente-privee/influxdb-relay
    cp ~/go/bin/influxdb-relay /usr/local/bin/influxdb-relay
    chmod 755 /usr/local/bin/influxdb-relay
    mkdir -p /etc/influxdb-relay
    cp ~/go/src/github.com/vente-privee/influxdb-relay/examples/sample.conf \
   /etc/influxdb-relay/influxdb-relay.conf
    
fi  

if [ ! -z ${CONF_KEEPALIVED+x} ] && [ ${CONF_KEEPALIVED} == "yes" ]; then
    #-----------------------------------------------------#
    ### Install KEEPALIVED
    #-----------------------------------------------------#
    echo "Installing keepalived"
    yum install -y keepalived
    systemctl enable keepalived
fi

if [ ! -z ${CONF_LDAP+x} ] && [ ${CONF_LDAP} == "yes" ]; then
    echo "Installing LDAP"
     #-----------------------------------------------------#
    ### Install LDAP
    #-----------------------------------------------------#
    # https://www.itzgeek.com/how-tos/linux/centos-how-tos/step-step-openldap-server-configuration-centos-7-rhel-7.html
    yum -y install openldap compat-openldap openldap-clients openldap-servers openldap-servers-sql openldap-devel
    systemctl enable slapd
    
fi  

if [ ! -z ${CONF_NAGVIS+x} ] && [ ${CONF_NAGVIS} == "yes" ]; then
    #-----------------------------------------------------#
    ### Install Nagivs
    #-----------------------------------------------------#
    if [ ! -d "/usr/share/nagvis" ]; then
        echo "Installing Nagvis"
        yum install php php-mysql php-pdo php-gd php-mbstring  graphviz -y
        wget https://www.nagvis.org/share/nagvis-1.9.10.tar.gz
        tar -xvzf nagvis-1.9.10.tar.gz
        cd nagvis-1.9.10
        ./install.sh -s icinga2 -n /usr/share/icinga2 -p /usr/share/nagvis -u apache -g apache -w /etc/httpd/conf.d -i mklivestatus -l tcp:localhost:6558 -a y -c y -r -F -q
    fi
fi    

if [ ! -z ${CONF_NFS+x} ] && [ ${CONF_NFS} == "yes" ]; then
    echo "Installing NSF"
    #-----------------------------------------------------#
    ### Install NFS
    #-----------------------------------------------------#
    yum install -y nfs-utils libnfsidmap
    systemctl enable rpcbind
    systemctl enable nfs-server
fi    

#PNP 
# if [ ! -d "/usr/local/pnp4nagios" ]; then
#     echo "Installing PNP4Nagios"
#     yum install rrdtool rrdtool-perl -y
#     wget https://github.com/lingej/pnp4nagios/archive/0.6.26.tar.gz
#     tar -zvxf 0.6.26.tar.gz
#     cd pnp4nagios-0.6.26
#     ./configure
#     make all
#     make fullinstall
#     # systemctl enable npcd
#     # systemctl start npcd
#     mv /usr/local/pnp4nagios/share/install.php /usr/local/pnp4nagios/share/install.php.ignore
#     ln -s /usr/local/pnp4nagios/ /var/www/html/pnp4nagios
# fi

#PNP
# if [ ! -d "/usr/share/icingaweb2/modules/pnp" ]; then
#     echo "Installing icingaWeb2 pnp"
#     cd /usr/share/icingaweb2/modules
#     git clone https://github.com/Icinga/icingaweb2-module-pnp.git pnp
#     # icingacli module enable pnp
# fi


#-----------------------------------------------------#
### Install Graylogd
#-----------------------------------------------------#

#------------------- Finish ----------------
echo "Done!!!"


