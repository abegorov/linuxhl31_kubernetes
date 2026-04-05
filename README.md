# Деплой веб-проекта в Kubernetes

## Задание

Установить **Kubernetes** и развернуть в нём веб-портал. Настроить бэкап конфигурации кластера.

1. Развернуть кластер **Kubernetes** на виртуальных машинах (например, через **kubeadm**).
2. Создать манифесты для автоматического деплоя веб-портала (**nginx**, **wordpress** и т.д.).
3. Настроить **ConfigMap**, **Secret**, **Ingress** и другие необходимые ресурсы.
4. Настроить бэкап конфигурации кластера (манифесты и данные **etcd** или `kubectl get all --all-namespaces -o yaml`).

## Реализация

С помощью **kubeadm** поднимается кластер **kubernetes** из 3-х **control-plane** и 3-x **worker** с **flannel**, **certmanager**, **gateway api**, **envoy gateway**, **longhorn**. В нём разворачивается **wordress** (на **php-fpm**) с **mariadb**. Для публикации **wordpress** используется **angie**, которые запускается в качестве **sidecar** контейнера к **wordpress** и проксирует запросы к нему через `/run/php-fpm.sock`. Резервное копирование настраивается роль **kubernetes_backup** с помощью скрипта [backup.sh](/roles/kubernetes_backup/templates/backup.sh), который делает **snapshot** базы данных etcd и сохраняет все ресурсы, со всех namespace'ов.

Задание сделано так, чтобы его можно было запустить как в **Vagrant**, так и в **Yandex Cloud**. После запуска происходит развёртывание следующих виртуальных машин отказоустойчивого кластера **kubernetes**:

- **k8s-control-01** - узел kubernetes control plane;
- **k8s-control-02** - узел kubernetes control plane;
- **k8s-control-03** - узел kubernetes control plane;
- **k8s-worker-01** - узел kubernetes worker node;
- **k8s-worker-02** - узел kubernetes worker node;
- **k8s-worker-03** - узел kubernetes worker node.

В независимости от того, как созданы виртуальные машины, для их настройки запускается **Ansible Playbook** [provision.yml](provision.yml) который последовательно запускает следующие роли:

- **haproxy** - устанавливает и настраивает **haproxy** на **control plane** для проксирования порта 8443 на 6443 узлы **control plane**, а также 80 и 443 порты на 30080 и 30443 порты **worker** узлов (запускается только при разворачивании в **vagrant**, в **yandex cloud** используется **network load balancer**).
- **keepalived** - устанавливает и настраивает **keepalived** на общий адрес **192.168.56.11** для всех узлов **control plane** (запускается только при разворачивании в **vagrant**).
- **wait_connection** - ожидает доступность виртуальных машин (при разворачивании в **yandex cloud**).
- **disable_swap** - отключает использование swap.
- **docker_repo** - настраивает зеркало для репозитория **docker.io** для последующей установке **containerd.io**.
- **kubernetes** - поднимает кластер **kubernetes** с помощью **kubeadm**, также устанавливает **flannel**, **gateway api**, **certmanager** и **envoy-gateway-system**.
- **disk_facts** - собирает информацию о дисках и их сигнатурах (с помощью утилит `lsblk` и `wipefs`) на узлах **worker**.
- **disk_label** - разбивает диски и устанавливает на них **GPT Partition Label** для их дальнейшей идентификации на узлах **worker**.
- **mount** - форматрует диск под данные и монтриует его в `/var/lib/longhorn` на узлах **worker**.
- **longhorn** - устанавливает **longhorn**.
- **kubernetes_apply** - применяет дополнительные манифесты в директории [manifests](manifests).
- **etcdctl** - устанавливает **etcdctl** для резервного копирования базы данных кластера **kubernetes**.
- **kubernetes_backup** - настраивает регулярное копирование базы данных кластера **kubernetes** в `/srv/backup`.

Данные роли настраиваются с помощью переменных, определённых в следующих файлах:

- [group_vars/all/ansible.yml](group_vars/all/ansible.yml) - общие переменные **ansible** для всех узлов;
- [group_vars/all/k8s.yml](group_vars/all/k8s.yml) - адрес и порт **load balancer** для подключения к разворачиваемому кластеру **kubernetes**;
- [group_vars/all/kubernetes.yml](group_vars/all/kubernetes.yml) - настройки кластера **kubernetes** (аргументы для **kubelet**, список узлов **control plane**, сеть и интерфейс для **flannel**);
- [group_vars/control/etcdctl.yml](group_vars/control/etcdctl.yml) - перечень узлов кластера **etcd** для настройки утилиты **etcdctl**;
- [group_vars/control/haproxy.yml](group_vars/control/haproxy.yml) - конфигурация **haproxy**;
- [group_vars/control/keepalived.yml](group_vars/control/keepalived.yml) - конфигурация **keepalived**;
- [group_vars/control/kubernetes.yml](group_vars/control/kubernetes.yml) - параметры **kubeadm** поднятия кластера **kubernetes**, список дополнительных манифестов, которые нужно применить через роль **kubernetes_apply**;
- [group_vars/control/wordpress.yml](group_vars/control/wordpress.yml) - настройки для **wordpress** (генерация паролей для **mariadb**, версии образов, имя домена).
- [group_vars/worker/mount.yml](group_vars/worker/mount.yml) - настройки для ролей **disk_label** и **mount** для форматирования и монтирования `/var/lib/longhorn`.

Для разворачивания **wordpress** были написаны следующие манифесты для кластера **kubernetes** (они применяются через роль **kubernetes_apply**):

- [manifests/certmanager-selfsigned-issuer.yml](manifests/certmanager-selfsigned-issuer.yml) - эмитент для сертификата шлюза **kubernetes**;
- [manifests/certmanager-gateway.yml](anifests/certmanager-gateway.yml) - сертификат для шлюза;
- [manifests/eg-nodeport.yml](manifests/eg-nodeport.yml) - дополнительные настройки шлюза (чтобы он работал через **NodePort** сервис, а не **LoadBalancer**);
- [manifests/gateway.yml](manifests/gateway.yml) - шлюз;
- [manifests/http-to-https-redirect.yml](manifests/http-to-https-redirect.yml) - настройки шлюза для перенаправления **http** на **https**;
- [manifests/wordpress-mariadb-secret.yml](manifests/wordpress-mariadb-secret.yml) - пароли для **mariadb**;
- [manifests/wordpress-mariadb-service-headless.yml](manifests/wordpress-mariadb-service-headless.yml) - headless сервис для **mariadb**;
- [manifests/wordpress-mariadb-service.yml](manifests/wordpress-mariadb-service.yml) - сервис для подключения к **mariadb**;
- [manifests/wordpress-mariadb.yml](manifests/wordpress-mariadb.yml) - разворачивание **mariadb**;
- [manifests/wordpress-angie-config.yml](manifests/wordpress-angie-config.yml) - конфигурация **angie** для **wordpress** (`fastcgi_pass unix:/run/php-fpm.sock;`);
- [manifests/wordpress-config.yml](manifests/wordpress-config.yml) - конфигурация **php-fpm** для **wordpress** (`listen = /run/php-fpm.sock`);
- [manifests/wordpress-pvc.yml](manifests/wordpress-pvc.yml) - claim для общего тома **wordpress**;
- [manifests/wordpress-service.yml](manifests/wordpress-service.yml) - сервис для доступа к **wordpress** через **angie**;
- [manifests/wordpress.yml](manifests/wordpress.yml) - разворачивания **wordpress**;
- [manifests/wordpress-httproute.yml](manifests/wordpress-httproute.yml) - маршрут для **gateway api**.

## Запуск

### Общие требования

1. Необходимо установить **Ansible**.
2. Необходимо установить **kubernetes** модуль для **python** (python3-kubernetes).
3. Для разворачивания манифеста **envoy proxy** также нужен **helm** версии 3.

### Запуск в Yandex Cloud

1. Необходимо установить и настроить утилиту **yc** по инструкции [Начало работы с интерфейсом командной строки](https://yandex.cloud/ru/docs/cli/quickstart).
2. Необходимо установить **Terraform** по инструкции [Начало работы с Terraform](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart).
3. Необходимо перейти в папку проекта и запустить скрипт [up.sh](up.sh).

### Запуск в Vagrant (VirtualBox)

Необходимо скачать **VagrantBox** для **bento/ubuntu-24.04** версии **202510.26.0** и добавить его в **Vagrant** под именем **bento/ubuntu-24.04/202510.26.0**. Сделать это можно командами:

```shell
curl -OL https://app.vagrantup.com/bento/boxes/ubuntu-24.04/versions/202510.26.0/providers/virtualbox/amd64/vagrant.box
vagrant box add vagrant.box --name "bento/ubuntu-24.04/202510.26.0"
rm vagrant.box
```

После этого нужно сделать **vagrant up** в папке проекта.

## Проверка

Протестировано в **OpenSUSE Tumbleweed**:

- **Vagrant 2.4.9**
- **VirtualBox 7.2.6_SUSE r172322**
- **Ansible 2.20.4**
- **Python 3.13.12**
- **Python client for kubernetes 35.0.0**
- **kubectl v1.35.2**
- **helm v3.20.1**
- **Jinja2 3.1.6**
- **Terraform 1.14.6**

Проверим разворачивание кластера kubernetes:

```text
❯ kubectl --kubeconfig secrets/kubeconfig get nodes
NAME             STATUS   ROLES           AGE    VERSION
k8s-control-01   Ready    control-plane   138m   v1.35.3
k8s-control-02   Ready    control-plane   137m   v1.35.3
k8s-control-03   Ready    control-plane   137m   v1.35.3
k8s-worker-01    Ready    <none>          138m   v1.35.3
k8s-worker-02    Ready    <none>          138m   v1.35.3
k8s-worker-03    Ready    <none>          138m   v1.35.3
```

Проверим состояние подов во всех namespace'ах (wordpress находится в default namespace):

```text
❯ kubectl --kubeconfig secrets/kubeconfig get namespaces
NAME                   STATUS   AGE
cert-manager           Active   137m
default                Active   140m
envoy-gateway-system   Active   136m
kube-flannel           Active   138m
kube-node-lease        Active   140m
kube-public            Active   140m
kube-system            Active   140m
longhorn-system        Active   133m

❯ kubectl --kubeconfig secrets/kubeconfig -n kube-system get pods
NAME                                     READY   STATUS    RESTARTS   AGE
coredns-7d764666f9-fnpzm                 1/1     Running   0          141m
coredns-7d764666f9-mqsn9                 1/1     Running   0          141m
etcd-k8s-control-01                      1/1     Running   0          142m
etcd-k8s-control-02                      1/1     Running   0          140m
etcd-k8s-control-03                      1/1     Running   0          140m
kube-apiserver-k8s-control-01            1/1     Running   0          142m
kube-apiserver-k8s-control-02            1/1     Running   0          140m
kube-apiserver-k8s-control-03            1/1     Running   0          140m
kube-controller-manager-k8s-control-01   1/1     Running   0          142m
kube-controller-manager-k8s-control-02   1/1     Running   0          140m
kube-controller-manager-k8s-control-03   1/1     Running   0          140m
kube-proxy-c5bh6                         1/1     Running   0          141m
kube-proxy-clmkb                         1/1     Running   0          141m
kube-proxy-kjk4s                         1/1     Running   0          141m
kube-proxy-q9mb6                         1/1     Running   0          140m
kube-proxy-qrbhb                         1/1     Running   0          141m
kube-proxy-s8twl                         1/1     Running   0          140m
kube-scheduler-k8s-control-01            1/1     Running   0          142m
kube-scheduler-k8s-control-02            1/1     Running   0          140m
kube-scheduler-k8s-control-03            1/1     Running   0          140m

❯ kubectl --kubeconfig secrets/kubeconfig -n kube-flannel get pods
NAME                    READY   STATUS    RESTARTS   AGE
kube-flannel-ds-7b8bf   1/1     Running   0          140m
kube-flannel-ds-clkh9   1/1     Running   0          140m
kube-flannel-ds-csjtk   1/1     Running   0          140m
kube-flannel-ds-fv97r   1/1     Running   0          140m
kube-flannel-ds-h47cw   1/1     Running   0          140m
kube-flannel-ds-sp69b   1/1     Running   0          140m

❯ kubectl --kubeconfig secrets/kubeconfig -n cert-manager get pods
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-67596fb4d7-k5tqq             1/1     Running   0          140m
cert-manager-cainjector-5fcbcd7fb-vd25b   1/1     Running   0          140m
cert-manager-webhook-864d6c4d87-kmx6n     1/1     Running   0          140m

❯ kubectl --kubeconfig secrets/kubeconfig -n envoy-gateway-system get pods
NAME                                        READY   STATUS    RESTARTS   AGE
envoy-default-eg-e41e7b31-8555ff9dc-l5wqm   2/2     Running   0          135m
envoy-default-eg-e41e7b31-8555ff9dc-pw7hj   2/2     Running   0          135m
envoy-default-eg-e41e7b31-8555ff9dc-r6v94   2/2     Running   0          135m
envoy-gateway-65874d54bb-dfv4x              1/1     Running   0          139m

❯ kubectl --kubeconfig secrets/kubeconfig -n longhorn-system get pods
NAME                                                     READY   STATUS    RESTARTS       AGE
csi-attacher-589b76ddcb-7ncll                            1/1     Running   2 (132m ago)   135m
csi-attacher-589b76ddcb-gr727                            1/1     Running   1 (132m ago)   135m
csi-attacher-589b76ddcb-gxqbm                            1/1     Running   1 (132m ago)   135m
csi-provisioner-6d744bccdf-bn5lw                         1/1     Running   1 (132m ago)   135m
csi-provisioner-6d744bccdf-hrbhf                         1/1     Running   0              135m
csi-provisioner-6d744bccdf-k5hmr                         1/1     Running   0              135m
csi-resizer-64c678dd69-gmczt                             1/1     Running   0              135m
csi-resizer-64c678dd69-vkhxf                             1/1     Running   1 (132m ago)   135m
csi-resizer-64c678dd69-wqp5p                             1/1     Running   1 (132m ago)   135m
csi-snapshotter-559c9d464b-5m4bs                         1/1     Running   0              135m
csi-snapshotter-559c9d464b-vx2p4                         1/1     Running   1 (132m ago)   135m
csi-snapshotter-559c9d464b-w2hvh                         1/1     Running   1 (132m ago)   135m
engine-image-ei-75a03ec3-8xwlg                           1/1     Running   0              136m
engine-image-ei-75a03ec3-msw8c                           1/1     Running   0              136m
engine-image-ei-75a03ec3-wh5lv                           1/1     Running   0              136m
instance-manager-02b41d0079841b0070c5e87cfc6ccbff        1/1     Running   0              136m
instance-manager-0b5834ba041c743f263d4823b24ed139        1/1     Running   0              136m
instance-manager-eae307ad9893602e8d62dfc984884f1b        1/1     Running   0              136m
longhorn-csi-plugin-bfr4p                                3/3     Running   1 (132m ago)   135m
longhorn-csi-plugin-nsjzh                                3/3     Running   1 (132m ago)   135m
longhorn-csi-plugin-wfdhf                                3/3     Running   0              135m
longhorn-driver-deployer-7c956f8598-76lpc                1/1     Running   0              136m
longhorn-manager-2n6lg                                   2/2     Running   0              137m
longhorn-manager-q29nb                                   2/2     Running   0              137m
longhorn-manager-trgx9                                   2/2     Running   0              137m
longhorn-ui-78cf85579b-bg459                             1/1     Running   0              136m
longhorn-ui-78cf85579b-tzzfw                             1/1     Running   0              136m
share-manager-pvc-1f40e74e-a2f0-4508-9b5c-47ff24a5ce6b   1/1     Running   0              130m

❯ kubectl --kubeconfig secrets/kubeconfig -n default get pods
NAME                        READY   STATUS    RESTARTS       AGE
wordpress-f478b6ddc-8pzll   2/2     Running   1 (128m ago)   131m
wordpress-f478b6ddc-cmfqh   2/2     Running   1 (128m ago)   131m
wordpress-f478b6ddc-hxww9   2/2     Running   1 (128m ago)   131m
wordpress-mariadb-0         1/1     Running   0              136m
```

Проверим сервисы в default namespace (как видно все они ClusterIP и недоступны с наружи кластера):

```text
❯ kubectl --kubeconfig secrets/kubeconfig get service
NAME                         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
kubernetes                   ClusterIP   10.96.0.1        <none>        443/TCP    145m
wordpress                    ClusterIP   10.106.123.172   <none>        80/TCP     132m
wordpress-mariadb            ClusterIP   10.110.126.74    <none>        3306/TCP   137m
wordpress-mariadb-headless   ClusterIP   None             <none>        3306/TCP   137m
```

Проверим сервисы для envoy gateway (доступен, который доступен снаружи, так как NodePort):

```text
❯ kubectl --kubeconfig secrets/kubeconfig -n envoy-gateway-system get service
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                            AGE
envoy-default-eg-e41e7b31   NodePort    10.96.180.167   <none>        80:30080/TCP,443:30443/TCP                         139m
envoy-gateway               ClusterIP   10.98.55.29     <none>        18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   143m
```

Попробуем посмотреть конфигурацию **angie**:

```text
❯ kubectl --kubeconfig secrets/kubeconfig debug -it wordpress-f478b6ddc-8pzll --profile=sysadmin --image=busybox --target angie-sidecar -- cat /proc/1/root/etc/angie/http.d/default.conf
Targeting container "angie-sidecar". If you don't see processes from this container it may be because the container runtime doesn't support this feature.
Defaulting debug container name to debugger-7s957.
server {
    listen 8080;
    server_name _;
    root /var/www/html;
    index index.php;

    access_log /dev/stdout;
    error_log /dev/stderr;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

Посмотрим IP адреса **load balancer** для доступа к **http gateway**:

```text
❯ terraform output
load_balancer = {
  "k8s-control-k8s" = "158.160.251.42"
  "k8s-worker-http" = "158.160.251.69"
  "k8s-worker-https" = "158.160.251.69"
}
private_ips = {
  "k8s-control-01" = "10.130.0.21"
  "k8s-control-02" = "10.130.0.22"
  "k8s-control-03" = "10.130.0.23"
  "k8s-worker-01" = "10.130.0.31"
  "k8s-worker-02" = "10.130.0.32"
  "k8s-worker-03" = "10.130.0.33"
}
public_ips = {
  "k8s-control-01" = "158.160.255.115"
  "k8s-control-02" = ""
  "k8s-control-03" = ""
  "k8s-worker-01" = ""
  "k8s-worker-02" = ""
  "k8s-worker-03" = ""
}
```

Шлюз находится по адресу 158.160.251.69, на нём должен быть **wordpress**:

[!wordpress](images/wordpress.png)

Проверим наличие резервных копий **etcd**:

```text
❯ ./ssh.sh k8s-control-01 sudo ls -la /srv/backup
total 84232
drwxrwx--- 2 root root    4096 Apr  5 14:21 .
drwxr-xr-x 3 root root    4096 Apr  5 11:36 ..
-rw-r----- 1 root root 5038270 Apr  5 11:41 20260405_114016Z.tar.zst
-rw-r----- 1 root root 5059652 Apr  5 11:51 20260405_115026Z.tar.zst
-rw-r----- 1 root root 5068714 Apr  5 12:01 20260405_120026Z.tar.zst
-rw-r----- 1 root root 5083403 Apr  5 12:11 20260405_121026Z.tar.zst
-rw-r----- 1 root root 5074728 Apr  5 12:21 20260405_122026Z.tar.zst
-rw-r----- 1 root root 5070761 Apr  5 12:31 20260405_123026Z.tar.zst
-rw-r----- 1 root root 5073351 Apr  5 12:41 20260405_124026Z.tar.zst
-rw-r----- 1 root root 5076546 Apr  5 12:51 20260405_125023Z.tar.zst
-rw-r----- 1 root root 5076218 Apr  5 13:01 20260405_130016Z.tar.zst
-rw-r----- 1 root root 5076102 Apr  5 13:11 20260405_131026Z.tar.zst
-rw-r----- 1 root root 5072970 Apr  5 13:21 20260405_132006Z.tar.zst
-rw-r----- 1 root root 5074672 Apr  5 13:31 20260405_133026Z.tar.zst
-rw-r----- 1 root root 5070624 Apr  5 13:41 20260405_134026Z.tar.zst
-rw-r----- 1 root root 5074405 Apr  5 13:51 20260405_135026Z.tar.zst
-rw-r----- 1 root root 5071334 Apr  5 14:01 20260405_140016Z.tar.zst
-rw-r----- 1 root root 5069412 Apr  5 14:11 20260405_141026Z.tar.zst
-rw-r----- 1 root root 5081179 Apr  5 14:21 20260405_142015Z.tar.zst
```

Проверим содержимое этих копий:

```text
❯ ./ssh.sh k8s-control-01 sudo tar tvf /srv/backup/20260405_142015Z.tar.zst
drwxr-x--- root/root         0 2026-04-05 14:21 ./
drwxr-x--- root/root         0 2026-04-05 14:21 ./longhorn-system/
-rw-r----- root/root     22786 2026-04-05 14:21 ./longhorn-system/deployments.apps.yaml
-rw-r----- root/root      8614 2026-04-05 14:21 ./longhorn-system/endpointslices.discovery.k8s.io.yaml
-rw-r----- root/root      4301 2026-04-05 14:21 ./longhorn-system/services.yaml
-rw-r----- root/root      4199 2026-04-05 14:21 ./longhorn-system/secrets.yaml
-rw-r----- root/root     21172 2026-04-05 14:21 ./longhorn-system/replicasets.apps.yaml
-rw-r----- root/root     15063 2026-04-05 14:21 ./longhorn-system/controllerrevisions.apps.yaml
-rw-r----- root/root      1308 2026-04-05 14:21 ./longhorn-system/roles.rbac.authorization.k8s.io.yaml
-rw-r----- root/root      1407 2026-04-05 14:21 ./longhorn-system/serviceaccounts.yaml
-rw-r----- root/root       742 2026-04-05 14:21 ./longhorn-system/backuptargets.longhorn.io.yaml
-rw-r----- root/root     14975 2026-04-05 14:21 ./longhorn-system/replicas.longhorn.io.yaml
-rw-r----- root/root      4244 2026-04-05 14:21 ./longhorn-system/poddisruptionbudgets.policy.yaml
-rw-r----- root/root    186992 2026-04-05 14:21 ./longhorn-system/pods.yaml
-rw-r----- root/root       996 2026-04-05 14:21 ./longhorn-system/sharemanagers.longhorn.io.yaml
-rw-r----- root/root      5846 2026-04-05 14:21 ./longhorn-system/endpoints.yaml
-rw-r----- root/root      7488 2026-04-05 14:21 ./longhorn-system/volumes.longhorn.io.yaml
-rw-r----- root/root      9905 2026-04-05 14:21 ./longhorn-system/nodes.longhorn.io.yaml
-rw-r----- root/root      4413 2026-04-05 14:21 ./longhorn-system/configmaps.yaml
-rw-r----- root/root     14946 2026-04-05 14:21 ./longhorn-system/daemonsets.apps.yaml
-rw-r----- root/root      9433 2026-04-05 14:21 ./longhorn-system/instancemanagers.longhorn.io.yaml
-rw-r----- root/root      2791 2026-04-05 14:21 ./longhorn-system/leases.coordination.k8s.io.yaml
-rw-r----- root/root       498 2026-04-05 14:21 ./longhorn-system/rolebindings.rbac.authorization.k8s.io.yaml
-rw-r----- root/root      1338 2026-04-05 14:21 ./longhorn-system/engineimages.longhorn.io.yaml
-rw-r----- root/root      9948 2026-04-05 14:21 ./longhorn-system/engines.longhorn.io.yaml
-rw-r----- root/root      5128 2026-04-05 14:21 ./longhorn-system/volumeattachments.longhorn.io.yaml
-rw-r----- root/root     41063 2026-04-05 14:21 ./longhorn-system/settings.longhorn.io.yaml
drwxr-x--- root/root         0 2026-04-05 14:21 ./kube-system/
-rw-r----- root/root      4292 2026-04-05 14:21 ./kube-system/deployments.apps.yaml
-rw-r----- root/root      1621 2026-04-05 14:21 ./kube-system/endpointslices.discovery.k8s.io.yaml
-rw-r----- root/root       989 2026-04-05 14:21 ./kube-system/services.yaml
-rw-r----- root/root      1261 2026-04-05 14:21 ./kube-system/secrets.yaml
-rw-r----- root/root      4049 2026-04-05 14:21 ./kube-system/replicasets.apps.yaml
-rw-r----- root/root      2563 2026-04-05 14:21 ./kube-system/controllerrevisions.apps.yaml
-rw-r----- root/root      6696 2026-04-05 14:21 ./kube-system/roles.rbac.authorization.k8s.io.yaml
-rw-r----- root/root      9093 2026-04-05 14:21 ./kube-system/serviceaccounts.yaml
-rw-r----- root/root    118603 2026-04-05 14:21 ./kube-system/pods.yaml
-rw-r----- root/root      2438 2026-04-05 14:21 ./kube-system/events.yaml
-rw-r----- root/root      1161 2026-04-05 14:21 ./kube-system/endpoints.yaml
-rw-r----- root/root     11325 2026-04-05 14:21 ./kube-system/configmaps.yaml
-rw-r----- root/root      2559 2026-04-05 14:21 ./kube-system/daemonsets.apps.yaml
-rw-r----- root/root      2579 2026-04-05 14:21 ./kube-system/events.events.k8s.io.yaml
-rw-r----- root/root      3765 2026-04-05 14:21 ./kube-system/leases.coordination.k8s.io.yaml
-rw-r----- root/root      7526 2026-04-05 14:21 ./kube-system/rolebindings.rbac.authorization.k8s.io.yaml
-rw------- root/root  25219104 2026-04-05 14:20 ./snapshot.db
drwxr-x--- root/root         0 2026-04-05 14:20 ./envoy-gateway-system/
-rw-r----- root/root     20049 2026-04-05 14:20 ./envoy-gateway-system/deployments.apps.yaml
-rw-r----- root/root      3714 2026-04-05 14:20 ./envoy-gateway-system/endpointslices.discovery.k8s.io.yaml
-rw-r----- root/root      2819 2026-04-05 14:20 ./envoy-gateway-system/services.yaml
-rw-r----- root/root   1394830 2026-04-05 14:20 ./envoy-gateway-system/secrets.yaml
-rw-r----- root/root      1008 2026-04-05 14:20 ./envoy-gateway-system/envoyproxies.gateway.envoyproxy.io.yaml
-rw-r----- root/root     19278 2026-04-05 14:20 ./envoy-gateway-system/replicasets.apps.yaml
-rw-r----- root/root      3030 2026-04-05 14:20 ./envoy-gateway-system/roles.rbac.authorization.k8s.io.yaml
-rw-r----- root/root      2090 2026-04-05 14:20 ./envoy-gateway-system/serviceaccounts.yaml
-rw-r----- root/root     52642 2026-04-05 14:20 ./envoy-gateway-system/pods.yaml
-rw-r----- root/root      2734 2026-04-05 14:20 ./envoy-gateway-system/endpoints.yaml
-rw-r----- root/root      4438 2026-04-05 14:20 ./envoy-gateway-system/configmaps.yaml
-rw-r----- root/root       567 2026-04-05 14:20 ./envoy-gateway-system/leases.coordination.k8s.io.yaml
-rw-r----- root/root      2466 2026-04-05 14:20 ./envoy-gateway-system/rolebindings.rbac.authorization.k8s.io.yaml
drwxr-x--- root/root         0 2026-04-05 14:20 ./kube-flannel/
-rw-r----- root/root      4695 2026-04-05 14:20 ./kube-flannel/controllerrevisions.apps.yaml
-rw-r----- root/root       534 2026-04-05 14:20 ./kube-flannel/serviceaccounts.yaml
-rw-r----- root/root     59886 2026-04-05 14:20 ./kube-flannel/pods.yaml
-rw-r----- root/root      2723 2026-04-05 14:20 ./kube-flannel/configmaps.yaml
-rw-r----- root/root      4567 2026-04-05 14:20 ./kube-flannel/daemonsets.apps.yaml
drwxr-x--- root/root         0 2026-04-05 14:20 ./cert-manager/
-rw-r----- root/root     11373 2026-04-05 14:20 ./cert-manager/deployments.apps.yaml
-rw-r----- root/root      4122 2026-04-05 14:20 ./cert-manager/endpointslices.discovery.k8s.io.yaml
-rw-r----- root/root      2914 2026-04-05 14:20 ./cert-manager/services.yaml
-rw-r----- root/root      2710 2026-04-05 14:20 ./cert-manager/secrets.yaml
-rw-r----- root/root     10635 2026-04-05 14:20 ./cert-manager/replicasets.apps.yaml
-rw-r----- root/root      1376 2026-04-05 14:20 ./cert-manager/roles.rbac.authorization.k8s.io.yaml
-rw-r----- root/root      1704 2026-04-05 14:20 ./cert-manager/serviceaccounts.yaml
-rw-r----- root/root     15911 2026-04-05 14:20 ./cert-manager/pods.yaml
-rw-r----- root/root      2853 2026-04-05 14:20 ./cert-manager/endpoints.yaml
-rw-r----- root/root      1834 2026-04-05 14:20 ./cert-manager/configmaps.yaml
-rw-r----- root/root      1406 2026-04-05 14:20 ./cert-manager/rolebindings.rbac.authorization.k8s.io.yaml
drwxr-x--- root/root         0 2026-04-05 14:21 ./kube-public/
-rw-r----- root/root      1193 2026-04-05 14:21 ./kube-public/roles.rbac.authorization.k8s.io.yaml
-rw-r----- root/root       281 2026-04-05 14:20 ./kube-public/serviceaccounts.yaml
-rw-r----- root/root      4016 2026-04-05 14:20 ./kube-public/configmaps.yaml
-rw-r----- root/root      1144 2026-04-05 14:21 ./kube-public/rolebindings.rbac.authorization.k8s.io.yaml
drwxr-x--- root/root         0 2026-04-05 14:20 ./kube-node-lease/
-rw-r----- root/root       285 2026-04-05 14:20 ./kube-node-lease/serviceaccounts.yaml
-rw-r----- root/root      1836 2026-04-05 14:20 ./kube-node-lease/configmaps.yaml
-rw-r----- root/root      3002 2026-04-05 14:20 ./kube-node-lease/leases.coordination.k8s.io.yaml
drwxr-x--- root/root         0 2026-04-05 14:20 ./default/
-rw-r----- root/root      6769 2026-04-05 14:20 ./default/deployments.apps.yaml
-rw-r----- root/root      5024 2026-04-05 14:20 ./default/endpointslices.discovery.k8s.io.yaml
-rw-r----- root/root      3155 2026-04-05 14:20 ./default/services.yaml
-rw-r----- root/root       505 2026-04-05 14:20 ./default/issuers.cert-manager.io.yaml
-rw-r----- root/root      6267 2026-04-05 14:20 ./default/secrets.yaml
-rw-r----- root/root      6521 2026-04-05 14:20 ./default/replicasets.apps.yaml
-rw-r----- root/root       805 2026-04-05 14:20 ./default/certificates.cert-manager.io.yaml
-rw-r----- root/root      5119 2026-04-05 14:20 ./default/statefulsets.apps.yaml
-rw-r----- root/root      4438 2026-04-05 14:20 ./default/controllerrevisions.apps.yaml
-rw-r----- root/root      5899 2026-04-05 14:20 ./default/certificaterequests.cert-manager.io.yaml
-rw-r----- root/root       277 2026-04-05 14:20 ./default/serviceaccounts.yaml
-rw-r----- root/root     42526 2026-04-05 14:20 ./default/pods.yaml
-rw-r----- root/root     15294 2026-04-05 14:20 ./default/events.yaml
-rw-r----- root/root      2532 2026-04-05 14:20 ./default/httproutes.gateway.networking.k8s.io.yaml
-rw-r----- root/root      3440 2026-04-05 14:20 ./default/endpoints.yaml
-rw-r----- root/root      3236 2026-04-05 14:20 ./default/gateways.gateway.networking.k8s.io.yaml
-rw-r----- root/root      3238 2026-04-05 14:20 ./default/configmaps.yaml
-rw-r----- root/root     16187 2026-04-05 14:20 ./default/events.events.k8s.io.yaml
-rw-r----- root/root      2020 2026-04-05 14:20 ./default/persistentvolumeclaims.yaml
```

Как видно файл `snapshot.db` присутствует в архиве. Резервное копирование томов **longhorn** можно выполнить через **Volumes -> Create Backup** или **Recurring Jobs -> Create Backup** на **longhorn dashboard**:

```text
❯ kubectl --kubeconfig secrets/kubeconfig -n longhorn-system port-forward services/longhorn-frontend 8080:80
Forwarding from 127.0.0.1:8080 -> 8000
Forwarding from [::1]:8080 -> 8000
```

[!longhorn volumes](images/volumes.png)
