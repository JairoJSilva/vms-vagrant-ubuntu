#!/bin/bash

# Função para solicitar entrada do usuário
function prompt() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3

    if [ -z "$default_value" ]; then
        read -p "$prompt_text: " $var_name
    else
        read -p "$prompt_text [$default_value]: " $var_name
        eval $var_name=\${$var_name:-$default_value}
    fi
}

# Solicitar informações ao usuário
prompt "CLUSTER_NAME" "Digite o nome do cluster" "mycluster"
prompt "BIND_NET_ADDR" "Digite o endereço da rede de binding (ex: 192.168.1.0)"
prompt "NODE1_NAME" "Digite o nome ou IP do Node 1"
prompt "NODE1_ID" "Digite o ID do Node 1" "1"
prompt "NODE2_NAME" "Digite o nome ou IP do Node 2"
prompt "NODE2_ID" "Digite o ID do Node 2" "2"
prompt "FLOATING_IP" "Digite o IP flutuante (ex: 192.168.1.100)"

# Atualizar e instalar pacotes necessários
sudo apt update
sudo apt upgrade -y
sudo apt install -y pacemaker corosync

# Configurar Corosync
sudo tee /etc/corosync/corosync.conf > /dev/null <<EOF
totem {
    version: 2
    secauth: on
    cluster_name: $CLUSTER_NAME
    transport: udpu
    interface {
        ringnumber: 0
        bindnetaddr: $BIND_NET_ADDR
        mcastport: 5405
    }
}

nodelist {
    node {
        ring0_addr: $NODE1_NAME
        nodeid: $NODE1_ID
    }
    node {
        ring0_addr: $NODE2_NAME
        nodeid: $NODE2_ID
    }
}

quorum {
    provider: corosync_votequorum
    two_node: 1
}

logging {
    to_syslog: yes
}
EOF

# Configurar Pacemaker
sudo tee /etc/pacemaker/cib.xml > /dev/null <<EOF
<cib>
    <configuration>
        <crm_config>
            <cluster_property_set id="cib-bootstrap-options">
                <nvpair id="cib-bootstrap-options-have-watchdog" name="have-watchdog" value="false"/>
                <nvpair id="cib-bootstrap-options-stonith-enabled" name="stonith-enabled" value="false"/>
                <nvpair id="cib-bootstrap-options-no-quorum-policy" name="no-quorum-policy" value="ignore"/>
            </cluster_property_set>
        </crm_config>
        <nodes>
            <node id="$NODE1_ID" uname="$NODE1_NAME"/>
            <node id="$NODE2_ID" uname="$NODE2_NAME"/>
        </nodes>
    </configuration>
</cib>
EOF

# Iniciar os serviços
sudo systemctl start corosync
sudo systemctl start pacemaker

# Verificar status do cluster
sudo crm status

# Adicionar recurso de IP flutuante
sudo crm configure primitive ClusterIP ocf:heartbeat:IPaddr2 params ip=$FLOATING_IP cidr_netmask=24 op monitor interval=30s

# Habilitar os serviços para iniciar automaticamente
sudo systemctl enable corosync
sudo systemctl enable pacemaker

echo "Configuração do Pacemaker concluída com sucesso."

