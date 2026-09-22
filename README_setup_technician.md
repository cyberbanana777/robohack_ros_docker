# Настройка образа системы.

## На jetson (организатор):
1. Изменить конфиг демона docker:
```bash
sudo tee /etc/docker/daemon.json <<'EOF'
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia",
    "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

sudo systemctl restart docker
```
2. Прописать маршрут сети по умолчанию 
```bash
sudo ip route add default via <ip-адрес хоста>
```
3. Настроить время в системе.

4. Развернуть docker-контейнер (или через dockerhub, или локально по ssh)

5. Сделать профиль student без sudo

6. Сделать автоматический запуск контейнера при пуске системы

7. Сделать так, чтобы когда юзер подключался по ssh - его сразу закидывало в контейнер



## На хост машине (ноутбук) (организатор)
1. Определить рабочий интерфейс, через который подлкючен jetson
```bash
ip a
```
вывод удет примерно таким:
```text
7: enxeaecdb7bfa86: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether ea:ec:db:7b:fa:86 brd ff:ff:ff:ff:ff:ff
    inet 192.168.55.100/24 brd 192.168.55.255 scope global dynamic noprefixroute enxeaecdb7bfa86
       valid_lft 11sec preferred_lft 11sec
    inet6 fe80::37b5:2cf2:7d78:e4f/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
8: enxeaecdb7bfa84: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN group default qlen 1000
    link/ether ea:ec:db:7b:fa:84 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::bcdf:3430:78f0:c1d/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
```
Нас интересует интерфейс, который имеет ip адрес в подсети 192.168.55.0
Далее выполним команду:
```bash
export JETSON_INTERFACE=<интересующий нас интерфейс>
```
2. Включить ip-forwarding
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

3. Узнать, какой интерфейс у ноута смотрит в интернет (обычно Wi-Fi):

```bash
ip route | grep default
```
Найдёшь что-то вроде default via ... dev wlp0s20f3 — это и есть твой "внешний" интерфейс.
```bash
export OUTSIDE_INTERFACE=<ваш внешний интерфейс>
```
4. Настроить NAT (MASQUERADE) и разрешить форвардинг:

```bash
sudo iptables -t nat -A POSTROUTING -o $OUTSIDE_INTERFACE -j MASQUERADE
sudo iptables -A FORWARD -i $JETSON_INTERFACE -o $OUTSIDE_INTERFACE -j ACCEPT
sudo iptables -A FORWARD -i $OUTSIDE_INTERFACE -o $JETSON_INTERFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
```

5. Настроить конфиг dds 
из папки репозитория запустить скрипт установки автосурса конфига
```bash
chmod +x autosource_ros2_env_host.sh
source autosource_ros2_env_host.sh
```
Также в конфиге `cyclonedds_config.sh` нужно заменить `wlp0s20f3` на свой интерфейс, который идёт на jetson (он же хранится в глобальной переменной`JETSON_INTERFACE`).
