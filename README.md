# Installation script address

Hysteria安装

# 安装脚本地址

### 安装Hysteria 1

```shell
wget -N --no-check-certificate https://raw.githubusercontent.com/yjlijiangdepc/install-hysteria-script/main/hy1/hysteria.sh && bash hysteria.sh
```

### 安装Hysteria 2

```shell
wget -N --no-check-certificate https://raw.githubusercontent.com/yjlijiangdepc/install-hysteria-script/main/hy2/hysteria.sh && bash hysteria.sh
```

### 安装 Acme 证书

```shell
wget -N --no-check-certificate https://raw.githubusercontent.com/yjlijiangdepc/install-hysteria-script/main/acme.sh && bash acme.sh
```
### 开启80端口

```shell
sudo ufw allow 80
```

### 开启443端口

```shell
sudo ufw allow 443
```

### 授权证书

```shell
sudo chmod +r /root/private.key
```

注: 1、安装时如果Acme申请证书的话一定要在安装Hysteria前先开启80和443端口，安装后要授权证书，再重启Hysteria，
    2、感谢(Misaka-blog)提供脚本。
