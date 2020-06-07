#!/usr/bin/sudo bash
REGION=us-west-2
BUCKET=ensstgcicd
{
echo "Cleaning up and installing common yum packages"
yum clean all 
yum update -y 
yum install -y unzip firewalld 

echo "Installing AWS CLI"
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip" 
unzip -q awscli-bundle.zip 
./awscli-bundle/install -i /usr/local/aws -b /bin/aws 
aws configure set region ${REGION}
aws s3 cp s3://${BUCKET}/configs-v1/common/install-ssmagent.sh - | bash

echo "Adding EPEL repo..."
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
echo "Installing some base packages and..."
echo "...domain/realm joining additions as well as openscap and the security guide for hardening"
echo "...adding growpart and Python PIP for the aws tool installation"
yum install -y yum-utils cifs-utils screen deltarpm wget \
      aide chrony samba-common-tools sssd-ad sssd adcli realmd oddjob oddjob-mkhomedir openscap-scanner scap-security-guide \
      cloud-utils-growpart mailx

groupadd -g 91 tomcat
useradd -g tomcat -u 91 -c "Apache Tomcat" -s /sbin/nologin -d /opt/tomcat tomcat
install -d -m 700 -o tomcat -g tomcat /opt/tomcat/.ssh

echo "setting up mail subsystem"
systemctl enable postfix
postconf relayhost=mailhost.$(hostname -d):25
grep -qr '^root:' /etc/aliases || { echo "root: sysalerts@ensocare.com" | tee -a /etc/aliases && newaliases; }
service postfix restart

echo "setting up a quick script to join the domain with"
cat << EOF > ~/sssdfix
s/(use_fully_qualified_names =).*/\1 False/g
s/(fallback_homedir = \/home\/%u).*/\1/g
EOF

echo "Setting up /usr/local/bin/quickjoin.sh"
#This is separate in case the first time it gets run, something isn't done right.
cat << EOF > /usr/local/bin/quickjoin.sh
read -p "Enter a username allowed to join the domain: " -r
realm join -U \${REPLY} && \
sed -i -rf ~/sssdfix /etc/sssd/sssd.conf && \
authconfig --disableldap --disableldapauth --updateall && \
authconfig --enablesssd --enablesssdauth --enablemkhomedir --update
echo "Reboot is required now to enable FIPS and other security mechanisms."
EOF
chmod +x /usr/local/bin/quickjoin.sh

firewall-offline-cmd --add-service ssh || true

} | tee -a ~/firstboot.log