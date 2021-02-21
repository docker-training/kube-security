#!/bin/bash

# Script automates the creation and deployment of SSL certificates used to create Harbor instance with configuring Docker.  Script also configures cluster nodes to connect to the Harbor instance.  Script is for lab purposes.

# Script Requirements:
# - the registry node must have the /etc/hosts file pre-configured IPs for:
#   - master
#   - etcd0
#   - node0
#   - node1
#   - registry AND reg.local (pointing to the same IP address)

reg_name=reg.local
public=$(echo $PublicIP)
private=$(echo $PrivateIP)

generate_CA_cert()
{
	touch ~/.rnd
	openssl genrsa -out ca.key 4096
	openssl req -x509 -new -nodes -sha512 -days 3650 \
		-subj "/C=US/ST=CA/L=Campbell/O=Mirantis/OU=Training/CN=$reg_name" \
		-key ca.key \
		-out ca.crt
}

generate_server_cert()
{
	openssl genrsa -out $reg_name.key 4096
	openssl req -sha512 -new \
		-subj "/C=US/ST=CA/L=Campbell/O=Mirantis/OU=Training/CN=$reg_name" \
		-key $reg_name.key \
		-out $reg_name.csr

	cat > temp.txt <<- "EOF"
	authorityKeyIdentifier=keyid,issuer
	basicConstraints=CA:FALSE
	keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
	extendedKeyUsage = serverAuth
	subjectAltName = @alt_names

	[alt_names]
	IP.1=$PrivateIP
	IP.2=$PublicIP
    DNS.1=$reg_name
	DNS.2=reg
	DNS.3=registry
	EOF

	while read line
	do
		eval echo "$line"
	done < "./temp.txt" > v3.ext
	rm temp.txt

    # Creating server certificate
	openssl x509 -req -sha512 -days 3650 \
		-extfile v3.ext \
		-CA ca.crt -CAkey ca.key -CAcreateserial \
		-in $reg_name.csr \
		-out $reg_name.crt

	# Creating .cert for Docker requirement
	openssl x509 -inform PEM \
            -in $reg_name.crt \
            -out $reg_name.cert
}

implement_certs()
{
	# Copying cert and key into place for Harbor to read
	sudo mkdir -p /data/cert
	sudo cp $reg_name.crt /data/cert/
	sudo cp $reg_name.key /data/cert/

	# Implementing cert and key for Docker to read
	sudo mkdir -p /etc/docker/certs.d/$reg_name/
	sudo cp $reg_name.{cert,key} /etc/docker/certs.d/$reg_name/
	sudo cp ca.crt /etc/docker/certs.d/$reg_name/

    # Copying CA certificate to verify registry trust of docker client
    sudo cp ca.crt /usr/local/share/ca-certificates/$reg_name.crt
    sudo update-ca-certificates

	printf '{\n   "live-restore": true\n}\n' | \
        sudo tee -a /etc/docker/daemon.json

    sudo systemctl restart docker
}

configure_cluster_nodes()
{
    # Configuring cluster nodes to use Harbor registry
    for node in master node0 node1
    do
        scp $reg_name.{key,crt,cert} $node:~/
        scp ca.crt $node:~/
        ssh $node "sudo mkdir -p /etc/docker/certs.d/$reg_name/ && \
	               sudo cp $reg_name.{key,cert} /etc/docker/certs.d/$reg_name/ && \
                   sudo cp ca.crt /usr/local/share/ca-certificates/$reg_name.crt && \
                   sudo update-ca-certificates && \
                   sudo systemctl restart docker"
    done
}


generate_CA_cert
generate_server_cert
implement_certs
configure_cluster_nodes
