# Деплой веб-проекта в Kubernetes

## Задание

Установить **Kubernetes** и развернуть в нём веб-портал. Настроить бэкап конфигурации кластера.

1. Развернуть кластер **Kubernetes** на виртуальных машинах (например, через **kubeadm**).
2. Создать манифесты для автоматического деплоя веб-портала (**nginx**, **wordpress** и т.д.).
3. Настроить **ConfigMap**, **Secret**, **Ingress** и другие необходимые ресурсы.
4. Настроить бэкап конфигурации кластера (манифесты и данные **etcd** или `kubectl get all --all-namespaces -o yaml`).

## Реализация

## Запуск

### Общие требования

1. Необходимо установить **Ansible**.
2. Необходимо установить **kubernetes** модуль для **python** (python3-kubernetes).
3. Для разворачивания манифеста **envoy proxy** также нужен **helm**.

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
- **Ansible 2.20.3**
- **Python 3.13.12**
- **Python client for kubernetes 35.0.0**
- **kubectl v1.35.2**
- **helm v3.20.1**
- **Jinja2 3.1.6**
- **Terraform 1.14.6**
