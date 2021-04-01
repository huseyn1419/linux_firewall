#!/bin/sh

version="0.1"
version_date="202103"

# check if root
if [ $(id -u) -ne 0 ] ; then echo "please run as root" ; exit 1 ; fi


echo -n "the network card connected to the external network (wan1):"
read wan1
echo -n "wan1 ip with netmask example: (/24):"
read wan1_ip
echo -n "wan1 gateway:"
read wan1_gateway

echo -n "the second network card connected to the external network (wan2):"
read wan2
echo -n "wan2 ip:"
read wan2_ip
echo -n "wan2 gateway:"
read wan2_gateway

#echo -n "the third network card connected to the external network (wan3):"
#read wan3
#echo -n "wan3 ip:"
#read wan3_ip

echo -n "the network card connected to the lan (lan1):"
read lan1
echo -n "lan1 ip:"
read lan1_ip
echo -n "lan1 network (example 192.168.2.0/24):"
read lan1_network

echo -n "domain: example.lan"
read domain
echo -n "radius server password:"
read radius_password



# enable packet forwarding
cat <<'eof' > /etc/sysctl.d/30-ipforward.conf
net.ipv4.ip_forward=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
eof

# static ip
systemctl enable systemd-networkd

cat <<eof > /etc/systemd/network/12-$wan1-static.network
[Match]
Name=$wan1

[Network]
Address=$wan1_ip
Gateway=$wan1_gateway
DNS=$wan1_gateway
eof

cat <<eof > /etc/systemd/network/13-$lan1-static.network
[Match]
Name=$lan1

[Network]
Address=$lan1_ip
eof


# iptables
systemctl enable iptables
iptables -t nat -A POSTROUTING -o $wan1 -j MASQUERADE
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $lan1 -o $wan1 -j ACCEPT

# iptables dhcp server rules
iptables -I INPUT -p udp --dport 67 -i $lan1 -j ACCEPT
iptables -I INPUT -p udp --dport 53 -s $lan1_network -j ACCEPT
iptables -I INPUT -p tcp --dport 53 -s $lan1_network -j ACCEPT

iptables-save -f /etc/iptables/rules.v4

# dnsmasq
cat <<eof > /etc/dnsmasq.conf
listen-address=::1,127.0.0.1,$lan1_ip
interface=$lan1
expand-hosts
bind-dynamic
domain=$domain
dhcp-range=192.168.4.50,192.168.5.254,255.255.254.0,24h

# set default gateway
dhcp-option=3,$lan1_ip

# set dns servers to announce
dhcp-option=6,$lan1_ip

cache-size=2000
eof




# freeradius
cat <<eof > /etc/freeradius/3.0/clients.conf
client "$lan1_network" {
  ipaddr = $lan1_network
  proto = udp
  secret = "$radius_password"
  require_message_authenticator = no
  nas_type = other
  ### login = !root ### 
  ### password = someadminpass ###
  limit {
    max_connections = 16
    lifetime = 0 
    idle_timeout = 30
  }
}
eof
