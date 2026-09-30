# Домашнее задание: PAM — пользователи, группы и ограничения

## Текст задания

1. Ограничить доступ к системе для всех пользователей, кроме группы администраторов, в выходные дни (суббота и воскресенье), за исключением праздничных дней.
2. ⭐ Предоставить определённому пользователю доступ к Docker и право перезапускать Docker-сервис.

## Стенд

| Параметр | Значение |
|---|---|
| ВМ | **Irida** (Proxmox VMID 103), Ubuntu 24.04, 192.168.1.233 |
| Пользователи | `otus`, `otusadm` (пароль `Otus2022!`), `dockuser` |
| Группа | `admin` (x:1003): otusadm, root, adrianl |
| PAM-модуль | `pam_exec` → `/usr/local/bin/login.sh` |

## Реализация

### 1. Пользователи и группа

```bash
useradd -m -s /bin/bash otusadm; useradd -m -s /bin/bash otus
echo 'otusadm:Otus2022!' | chpasswd; echo 'otus:Otus2022!' | chpasswd
groupadd -f admin
usermod -aG admin otusadm; usermod -aG admin root; usermod -aG admin adrianl
```

Результат: `admin:x:1003:otusadm,root,adrianl`

### 2. Скрипт контроля `/usr/local/bin/login.sh` (pam_exec)

В отличие от методички (простая проверка Sat/Sun), скрипт дополнительно учитывает праздники — это прямое требование ТЗ («за исключением праздничных дней»):

- Список праздников — по годам: `/etc/holidays.d/YYYY`, формат `MM-DD` (файл `holidays` в репозитории).
- Если сегодня **суббота/воскресенье** и **не праздник**: вход разрешён только членам группы `admin`, остальные получают отказ (и запись в syslog через `logger -t pam_login_denied`).
- В праздники и будни вход разрешён всем.

Подключение в `/etc/pam.d/sshd` (после `# Standard Un*x authentication`):

```
auth required pam_exec.so quiet /usr/local/bin/login.sh
```

### 3. Проверка (перевод системной даты на ВМ)

Т.к. проверка выполнялась в будний день, дата на ВМ переводилась вручную (`timedatectl set-ntp false; date MMDDhhmmYYYY.ss`), после тестов NTP включён обратно.

| Тест | Дата на ВМ | Пользователь | Результат |
|---|---|---|---|
| Будний день | Wed 30.09.2026 | otus | ✅ вход разрешён |
| Суббота | Sat 26.09.2026 | otus (не admin) | ✅ **отказ**: `Permission denied`; syslog: `pam_login_denied: user=otus denied: weekend, not in admin group` |
| Суббота | Sat 26.09.2026 | otusadm (admin) | ✅ вход разрешён (`date` → `Sat`) |
| Праздник в субботу | Sat 02.01.2027 (01-02 в списке) | otus | ✅ вход разрешён (`HOLIDAY_LOGIN_OK`) |
| Обычное воскресенье | Sun 10.01.2027 | otus | ✅ отказ |
| Обычное воскресенье | Sun 10.01.2027 | otusadm | ✅ вход разрешён (`OTUSADM_SUNDAY_OK`) |

Особенность проверки: pam_exec запускает скрипт на этапе `auth`, поэтому отказ выглядит как неверный пароль (`Permission denied`) — `quiet` скрывает вывод скрипта. Диагностика — через syslog (`pam_login_denied`).

### 4. ⭐ Docker-доступ для пользователя

Пользователь `dockuser`:

```bash
useradd -m -s /bin/bash dockuser
echo 'dockuser:Otus2022!' | chpasswd
usermod -aG docker dockuser
echo 'dockuser ALL=(root) NOPASSWD: /usr/bin/systemctl restart docker, /bin/systemctl restart docker' > /etc/sudoers.d/dockuser-docker
chmod 440 /etc/sudoers.d/dockuser-docker   # visudo -c: parsed OK
```

Проверка:

- `docker ps` под dockuser без sudo — работает (членство в группе `docker`).
- `sudo -n systemctl restart docker` → `RESTART_OK`, после перезапуска `docker run --rm hello-world` → `Hello from Docker!`.

## Файлы репозитория

| Файл | Назначение |
|---|---|
| `login.sh` | PAM-скрипт (копируется в `/usr/local/bin/login.sh`, chmod 755) |
| `holidays` | Список праздников (`/etc/holidays.d/YYYY`) |
| `sudoers.d-dockuser-docker` | Содержимое `/etc/sudoers.d/dockuser-docker` |

## Заметки

- `pam_time` не подошёл: не работает с локальными группами и не умеет праздники → `pam_exec` со скриптом.
- Праздники удобно вести по файлам на год: добавление нового года = один файл без правки PAM.
- Отказ pam_exec при `auth` маскируется под неверный пароль — это штатное поведение (не раскрывает причину наружу), для аудитории используется syslog.
