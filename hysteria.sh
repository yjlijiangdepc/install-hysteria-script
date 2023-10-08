#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

realip(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

inst_cert(){
    green "Hysteria 协议证书申请方式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 自签证书 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Acme 脚本自动申请"
    echo -e " ${GREEN}3.${PLAIN} 自定义证书路径"
    echo ""
    read -rp "请输入选项 [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        cert_path="/root/cert.crt"
        key_path="/root/private.key"

        chmod a+x /root # 让 Hysteria 主程序访问到 /root 目录

        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "检测到原有域名：$domain 的证书，正在应用"
            hy_domain=$domain
        else
            wget -N https://gitlab.com/Misaka-blog/acme-script/-/raw/main/acme.sh && bash acme.sh
            
            if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
                domain=$(cat /root/ca.log)
                hy_domain=$domain
            else
                red "证书申请失败，脚本退出" && exit
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "请输入公钥文件 crt 的路径：" cert_path
        yellow "公钥文件 crt 的路径：$certpath "
        read -p "请输入密钥文件 key 的路径：" key_path
        yellow "密钥文件 key 的路径：$keypath "
        read -p "请输入证书的域名：" domain
        yellow "证书域名：$domain"

        hy_domain=$domain
    else
        green "将使用自签证书作为 Hysteria 的节点证书"

        read -rp "请输入 Hysteria 2 自签证书地址 （去除https://） [回车默认]：" certsite
        [[ -z $certsite ]] && certsite="www.sony.com.cn"
        yellow "使用在 Hysteria 2 自签证书地址为：$certsite"

        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            systemctl stop warp-go >/dev/null 2>&1
            realip
            wg-quick up wgcf >/dev/null 2>&1
            systemctl start warp-go >/dev/null 2>&1
        else
            realip
        fi

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"

        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=$certsite"

        chmod 777 /etc/hysteria/cert.crt
        chmod 777 /etc/hysteria/private.key

        hy_domain="$certsite"
        domain="$certsite"
    fi
}

inst_pro(){
    green "Hysteria 节点协议如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} UDP ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} wechat-video"
    echo -e " ${GREEN}3.${PLAIN} faketcp"
    echo ""
    read -rp "请输入选项 [1-3]: " proInput
    if [[ $proInput == 2 ]]; then
        protocol="wehcat-video"
    elif [[ $proInput == 3 ]]; then
        protocol="faketcp"
    else
        protocol="udp"
    fi
    yellow "将使用 $protocol 作为 Hysteria 的节点协议"
}

inst_port(){
    iptables -t nat -F PREROUTING >/dev/null 2>&1

    read -p "设置 Hysteria 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    yellow "将在 Hysteria 节点使用的端口是：$port"
}

inst_jump(){
    green "Hysteria 端口使用模式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 单端口 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 端口跳跃"
    echo ""
    read -rp "请输入选项 [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "设置起始端口 (建议10000-65535之间)：" firstport
        read -p "设置末端口 (建议10000-65535之间，大于起始端口的数值)：" endport
        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "重新输入起始端口和末端口"
                    read -p "设置起始端口 (建议10000-65535之间)：" firstport
                    read -p "设置末端口 (建议10000-65535之间，大于起始端口的数值)：" endport
                fi
            done
        fi
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        netfilter-persistent save >/dev/null 2>&1
    else
        red "继续使用单端口模式"
    fi
}

inst_pwd(){
    read -p "设置 Hysteria 密码（直接回车随机密码）：" auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "使用在 Hysteria 节点的密码为：$auth_pwd"
}

inst_resolv(){
    green "Hysteria 域名解析模式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} IPv4 优先 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} IPv6 优先"
    echo ""
    read -rp "请输入选项 [1-2]: " resolvInput
    if [[ $resolvInput == 2 ]]; then
        yellow "Hysteria 域名解析模式已设置成 IPv6 优先"
        resolv=64
    else
        yellow "Hysteria 域名解析模式已设置成 IPv4 优先"
        resolv=46
    fi
}

inst_site(){
    read -rp "请输入 Hysteria 2 的伪装网站地址 （去除https://） [回车默认]：" proxysite
    [[ -z $proxysite ]] && proxysite="www.gamedeveloper.com"
    yellow "使用在 Hysteria 2 节点的伪装网站为：$proxysite"
}

inst_hyv1(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        red "检测到已安装 Hysteria 2，先卸载再安装 Hysteria 1！"
        exit 1
    fi

    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/yjlijiangdepc/install-hysteria-script/main/hy1/hysteria_install_server.sh
    bash hysteria_install_server.sh
    rm -f hysteria_install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria 1 安装成功！"
    else
        red "Hysteria 1 安装失败！重新运行脚本后安装"
    fi

    # 询问用户 Hysteria 配置
    inst_cert
    inst_pro
    inst_port && [[ $protocol == "udp" ]] && inst_jump
    inst_pwd
    inst_resolv

    # 设置 Hysteria 配置文件
    cat <<EOF > /etc/hysteria/config.json
{
    "protocol": "$protocol",
    "listen": ":$port",
    "resolve_preference": "$resolv",
    "cert": "$cert_path",
    "key": "$key_path",
    "alpn": "h3",
    "auth": {
        "mode": "password",
        "config": {
            "password": "$auth_pwd"
        }
    }
}
EOF

    # 确定最终入站端口范围
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # 给 IPv6 地址加中括号
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    # 判断证书是否为自签，如是则使用 IP 作为节点入站
    if [[ $hy_domain == "$certsite" ]]; then
        hy_domain=$last_ip
    fi

    # 设置 V2rayN 及 Clash Meta 配置文件
    mkdir /root/hy >/dev/null 2>&1
    cat << EOF > /root/hy/hy-client.json
{
    "protocol": "$protocol",
    "server": "$hy_domain:$last_port",
    "server_name": "$domain",
    "alpn": "h3",
    "up_mbps": 200,
    "down_mbps": 1000,
    "auth_str": "$auth_pwd",
    "insecure": true,
    "retry": 3,
    "retry_interval": 3,
    "fast_open": true,
    "lazy_start": true,
    "hop_interval": 60,
    "socks5": {
        "listen": "127.0.0.1:2689"
    }
}
EOF

    cat << EOF > /root/hy/clash-meta.yaml
mixed-port: 8890
external-controller: 127.0.0.1:2688
allow-lan: false
mode: rule
log-level: debug
ipv6: true
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
    - 114.114.114.114
proxies:
  - name: yjlijiangdepc-Hysteria1
    type: hysteria
    server: $hy_domain
    port: $last_port
    auth_str: $auth_pwd
    alpn:
      - h3
    protocol: $protocol
    up: 200
    down: 1000
    sni: $domain
    skip-cert-verify: true
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - yjlijiangdepc-Hysteria1
      
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF

    url="hysteria://$hy_domain:$last_port?protocol=$protocol&auth=$auth_pwd&peer=$domain&insecure=$true&upmbps=20&downmbps=100&alpn=h3#yjlijiangdepc-Hysteria1"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server

    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.json' ]]; then
        green "Hysteria 服务启动成功"
    else
        red "Hysteria-server 服务启动失败，请运行 systemctl status hysteria-server 查看服务状态并反馈，脚本退出" && exit 1
    fi

    showconf
}

unst_hyv1(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria.sh
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    green "Hysteria 1 彻底完成卸载！"
}

inst_hyv2(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        red "检测到已安装 Hysteria 2，先卸载再安装 Hysteria 1！"
        exit 1
    fi

    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/yjlijiangdepc/install-hysteria-script/main/hy2/hysteria_install_server.sh
    bash hysteria_install_server.sh
    rm -f hysteria_install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria 2 安装成功！"
    else
        red "Hysteria 2 安装失败！重新运行脚本后安装"
    fi

    # 询问用户 Hysteria 配置
    inst_cert
    inst_port
    inst_jump
    inst_pwd
    inst_site

    # 设置 Hysteria 配置文件
    cat << EOF > /etc/hysteria/config.yaml
listen: :$port

tls:
  cert: $cert_path
  key: $key_path

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true
EOF

    # 确定最终入站端口范围
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # 给 IPv6 地址加中括号
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    mkdir /root/hy
    cat << EOF > /root/hy/hy-client.yaml
server: $last_ip:$last_port

auth: $auth_pwd

tls:
  sni: $hy_domain
  insecure: true

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:2689

transport:
  udp:
    hopInterval: 30s 
EOF
    cat << EOF > /root/hy/hy-client.json
{
  "server": "$last_ip:$last_port",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "$hy_domain",
    "insecure": true
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "socks5": {
    "fastOpen": true,
    "listen": "127.0.0.1:2689"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

    url="hysteria2://$auth_pwd@$last_ip:$last_port/?insecure=1&sni=$hy_domain#yjlijiangdepc-Hysteria2"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.yaml' ]]; then
        green "Hysteria 2 服务启动成功"
    else
        red "Hysteria 2 服务启动失败，请运行 systemctl status hysteria-server 查看服务状态并反馈，脚本退出" && exit 1
    fi

    showconf
}

unst_hyv2(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria.sh
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    green "Hysteria 2 彻底完成卸载！"
}

starthysteria(){
    systemctl start hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

statushysteria(){
    systemctl status hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

stophysteria(){
    systemctl stop hysteria-server
    systemctl disable hysteria-server >/dev/null 2>&1
}

hy_switch(){
    yellow "请选择你需要的操作："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} 关闭 Hysteria 2"
    echo -e " ${GREEN}3.${PLAIN} 重启 Hysteria 2"
	echo -e " ${GREEN}3.${PLAIN} 查看服务器状态"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1 ) starthysteria ;;
        2 ) stophysteria ;;
        3 ) stophysteria && starthysteria ;;
	    4 ) statushysteria ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        oldport=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 1p | awk '{print $2}' | awk -F ":" '{print $2}')
    
        inst_port && inst_jump

        if [[ -n $firstport ]]; then
            last_port="$port,$firstport-$endport"
        else
            last_port=$port
        fi

        sed -i "1s#$oldport#$port#g" /etc/hysteria/config.yaml
        sed -i "1s#$oldport#$last_port#g" /root/hy/hy-client.yaml
        sed -i "2s#$oldport#$last_port#g" /root/hy/hy-client.json
        sed -i "1s#$oldport#$last_port#g" /root/hy/url.txt

        stophysteria && starthysteria

        green "Hysteria 2 端口已成功修改为：$port"
        yellow "手动更新客户端配置文件"
        showconf
    else
        old_port=$(cat /root/hy/hy-client.json | grep -w server | awk '{print $2}' | awk -F '"' '{ print $2}' | awk -F ':' '{ print $NF}')
        old_procotol=$(cat /etc/hysteria/config.json | grep protocol | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g" | sed "s/://g")

        inst_port

        # 判断协议是否为 udp，如为 udp 重新设置端口跳跃
        if [[ $old_procotol == "udp" ]]; then
            inst_jump
        fi

        if [[ -n $firstport ]]; then
            last_port="$port,$firstport-$endport"
        else
            last_port=$port
        fi

        sed -i "s/$old_port/$port/g" /etc/hysteria/config.json
        sed -i "s/$old_port/$last_port/g" /root/hy/hy-client.json
        sed -i "s/$old_port/$last_port/g" /root/hy/clash-meta.yaml
        sed -i "s/$old_port/$last_port/g" /root/hy/url.txt

        stophysteria && starthysteria

        green "Hysteria 1 端口已成功修改为：$port"
        yellow "手动更新客户端配置文件"
        showconf
    fi
}

changepasswd(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        old_pwd=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 15p | awk '{print $2}')

        inst_pwd

        sed -i "1s#$old_pwd#$auth_pwd#g" /etc/hysteria/config.yaml
        sed -i "1s#$old_pwd#$auth_pwd#g" /root/hy/hy-client.yaml
        sed -i "3s#$old_pwd#$auth_pwd#g" /root/hy/hy-client.json
        sed -i "s/$old_pwd/$auth_pwd/g" /root/hy/url.txt

        stophysteria && starthysteria

        green "Hysteria 2 密码已成功修改为：$auth_pwd"
        yellow "手动更新客户端配置文件"
        showconf
    else
        old_pwd=$(cat /etc/hysteria/config.json | grep password | sed -n 2p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

        inst_pwd

        sed -i "s/$old_pwd/$auth_pwd/g" /etc/hysteria/config.json
        sed -i "s/$old_pwd/$auth_pwd/g" /root/hy/hy-client.json
        sed -i "s/$old_pwd/$auth_pwd/g" /root/hy/clash-meta.yaml
        sed -i "s/$old_pwd/$auth_pwd/g" /root/hy/url.txt

        stophysteria && starthysteria

        green "Hysteria 1 节点密码已成功修改为：$auth_pwd"
        yellow "手动更新客户端配置文件"
        showconf
    fi
}

change_cert(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        old_cert=$(cat /etc/hysteria/config.yaml | grep cert | awk -F " " '{print $2}')
        old_key=$(cat /etc/hysteria/config.yaml | grep key | awk -F " " '{print $2}')
        old_hydomain=$(cat /root/hy/hy-client.yaml | grep sni | awk '{print $2}')

        inst_cert

        sed -i "s!$old_cert!$cert_path!g" /etc/hysteria/config.yaml
        sed -i "s!$old_key!$key_path!g" /etc/hysteria/config.yaml
        sed -i "6s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.yaml
        sed -i "5s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.json
        sed -i "s/$old_hydomain/$hy_domain/g" /root/hy/url.txt

        stophysteria && starthysteria

        green "Hysteria 2 证书类型已成功修改"
        yellow "手动更新客户端配置文件"
        showconf
    else
        old_cert=$(cat /etc/hysteria/config.json | grep cert | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
        old_key=$(cat /etc/hysteria/config.json | grep key | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
        old_server=$(cat /root/hy/hy-client.json | grep -w server | awk '{print $2}' | awk -F '"' '{ print $2}' | cut -d ':' -f 1)
        old_domain=$(cat /root/hy/hy-client.json | grep server_name | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

        inst_cert

        if [[ $hy_domain == "$certsite" ]]; then
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                hy_domain=$(curl -s4m8 ip.sb -k) || hy_domain="[$(curl -s6m8 ip.sb -k)]"
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                hy_domain=$(curl -s4m8 ip.sb -k) || hy_domain="[$(curl -s6m8 ip.sb -k)]"
            fi
        fi

        sed -i "s!$old_cert!$cert_path!g" /etc/hysteria/config.json
        sed -i "s!$old_key!$key_path!g" /etc/hysteria/config.json
        sed -i "3s/$old_server/$hy_domain/g" /root/hy/hy-client.json
        sed -i "4s/$old_domain/$domain/g" /root/hy/hy-client.json
        sed -i "18s/$old_server/$hy_domain/g" /root/hy/clash-meta.yaml
        sed -i "26s/$old_domain/$domain/g" /root/hy/clash-meta.yaml
        sed -i "s/$old_server/$hy_domain/g" /root/hy/url.txt
        sed -i "s/$old_domain/$domain/g" /root/hy/url.txt
        
        stophysteria && starthysteria
        green "Hysteria 1 证书类型已成功修改"
        yellow "手动更新客户端配置文件"
        showconf
    fi
}

change_pro(){
    old_pro=$(cat /etc/hysteria/config.json | grep protocol | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

    inst_pro

    sed -i "s/$old_pro/$protocol/g" /etc/hysteria/config.json
    sed -i "s/$old_pro/$protocol/g" /root/hy/hy-client.json
    sed -i "s/$old_pro/$protocol/g" /root/hy/clash-meta.yaml
    sed -i "s/$old_pro/$protocol/g" /root/hy/url.txt

    stophysteria && starthysteria

    green "Hysteria 1 协议已成功修改为：$protocol"
    yellow "手动更新客户端配置文件"
    showconf
}

change_resolv(){
    old_resolv=$(cat /etc/hysteria/config.json | grep resolv | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

    inst_resolv

    sed -i "s/$old_resolv/$resolv/g" /etc/hysteria/config.json

    stophysteria && starthysteria

    green "Hysteria 1 域名解析优先级已成功修改"
}

changeproxysite(){
    oldproxysite=$(cat /etc/hysteria/config.yaml | grep url | awk -F " " '{print $2}' | awk -F "https://" '{print $2}')
    
    inst_site

    sed -i "s#$oldproxysite#$proxysite#g" /etc/hysteria/config.yaml

    stophysteria && starthysteria

    green "Hysteria 2 伪装网站已成功修改为：$proxysite"
}

changeconf(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        green "Hysteria 2 配置变更选择如下:"
        echo -e " ${GREEN}1.${PLAIN} 修改端口"
        echo -e " ${GREEN}2.${PLAIN} 修改密码"
        echo -e " ${GREEN}3.${PLAIN} 修改证书类型"
        echo -e " ${GREEN}4.${PLAIN} 修改伪装网站"
        echo ""
        read -p " 请选择操作 [1-4]：" confAnswer
        case $confAnswer in
            1 ) changeport ;;
            2 ) changepasswd ;;
            3 ) change_cert ;;
            4 ) changeproxysite ;;
            * ) exit 1 ;;
        esac
    else
        green "Hysteria 配置变更选择如下:"
        echo -e " ${GREEN}1.${PLAIN} 修改端口"
        echo -e " ${GREEN}2.${PLAIN} 修改密码"
        echo -e " ${GREEN}3.${PLAIN} 修改证书类型"
        echo -e " ${GREEN}4.${PLAIN} 修改传输协议"
        echo -e " ${GREEN}5.${PLAIN} 修改域名解析优先级"
        echo ""
        read -p " 请选择操作 [1-5]：" confAnswer
        case $confAnswer in
            1 ) changeport ;;
            2 ) changepasswd ;;
            3 ) change_cert ;;
            4 ) change_pro ;;
            5 ) change_resolv ;;
            * ) exit 1 ;;
        esac
    fi
}

showconf(){
    if [[ -f "/etc/hysteria/config.yaml" ]]; then
        yellow "Hysteria 2 客户端 YAML 配置文件 hy-client.yaml 内容保存到 /root/hy/hy-client.yaml"
        red "$(cat /root/hy/hy-client.yaml)"
        yellow "Hysteria 2 客户端 JSON 配置文件 hy-client.json 内容保存到 /root/hy/hy-client.json"
        red "$(cat /root/hy/hy-client.json)"
        yellow "Hysteria 2 节点分享链接内容保存到 /root/hy/url.txt"
        red "$(cat /root/hy/url.txt)"
    else
        yellow "客户端配置文件 hy-client.json 内容保存到 /root/hy/hy-client.json"
        cat /root/hy/hy-client.json
        yellow "Clash Meta 客户端配置文件保存到 /root/hy/clash-meta.yaml"
        yellow "Hysteria 节点分享链接内容保存到 /root/hy/url.txt"
        red $(cat /root/hy/url.txt)
    fi
}

menu() {
    clear
    echo "#############################################################"
    echo -e "# ${GREEN}                  一键安装hysteria ${YELLOW}协议 ${PLAIN}                 #"
    echo -e "# ${GREEN}作者修改: ${PLAIN}YJLIJIANGDEPC  ${RED}(原脚本引用： MisakaNo の 小破站 ) ${PLAIN}#"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Hysteria 2"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Hysteria2、查看服务器状态"
    echo -e " ${GREEN}4.${PLAIN} 修改 Hysteria2 配置"
    echo -e " ${GREEN}5.${PLAIN} 显示 Hysteria2 配置文件"
    echo " -------------"
    echo -e " ${RED}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in
        1 ) insthysteria ;;
        2 ) unsthysteria ;;
        3 ) hysteriaswitch ;;
        4 ) changeconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu
