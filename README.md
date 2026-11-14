# SERV TikTok Clone — deployment on Proxmox

**[English](#english) | [Українська](#українська)**

> 🤖 Deployed by AI agent **Claude Opus 5.5** (Anthropic, Claude Code) · Розгорнуто AI-агентом **Claude Opus 5.5** (Anthropic, Claude Code)

Source project: <https://github.com/fraspess/Tiktok_Clone> (original description: [README.project.md](README.project.md), [README.uk.md](README.uk.md)).

---

## English

> 🤖 **This deployment was done by an AI agent: Claude Opus 5.5 (`claude-opus-5-5`) by Anthropic, working in Claude Code.**
>
> I am Claude, an AI model made by Anthropic. Here I worked as an agent inside Claude Code, Anthropic's command-line tool. The user gave me the task in plain Ukrainian. I did it myself through the terminal: I connected to Proxmox over SSH, created and configured the VM, installed Ubuntu and Docker, studied the project's code, built and started the containers, checked that everything works, and wrote this README. Where I needed a decision or access (credentials, the free IP address), I asked the user. Everything below is written in the first person, from me.

This repository is a copy of the TikTok Clone project plus the files I added to deploy it on a Proxmox VM over HTTPS. Below I describe, in my own words, everything I did.

### Result

| Item | Value |
| --- | --- |
| Proxmox host | `172.14.50.91` (PVE 9.1) |
| Virtual machine | VMID `1007`, name `1007serStep` |
| VM resources | 2 vCPU, 2 GB RAM (+4 GB swap file), 30 GB disk (local-lvm) |
| OS | Ubuntu 26.04.1 LTS (cloud image) |
| Docker | Docker Engine 29.9 + Compose plugin v5.7 |
| Application URL | **<https://172.14.50.81>** (port 443, HTTP 80 redirects to HTTPS) |
| Demo login | `string` / `String!1` (admin, from the project's seed data) |

### 1. Analyzing the project

Before deploying anything I read the source repository:

- `front/`: React 19 + Vite. It is built in Node and served by nginx. The API address is set at build time through `VITE_API_BASE_URL`.
- `back/Api`: .NET 10 API on port 8080 (REST, SignalR hubs `/hubs/*`, static `/uploads`, `/avatars`). On startup it applies EF Core migrations and seeds demo users.
- `back/VideoProcessor`: .NET worker that processes videos with FFmpeg and receives jobs from RabbitMQ.
- Infrastructure: PostgreSQL, Redis, RabbitMQ.
- `compose.local.yaml` runs everything over plain HTTP on localhost. `compose.server.yaml` is tied to the authors' production setup (duckdns domain, Let's Encrypt, Amazon S3), so I could not use it as is.

### 2. Creating the VM on Proxmox

I connected to Proxmox over SSH and found two Ubuntu images in ISO storage. I picked the newest one, `ubuntu-26.04-server-cloudimg-amd64.img`. It is a cloud image, so the system can be installed without the interactive installer, configured through cloud-init:

```bash
qm create 1007 --name 1007serStep --memory 2048 --balloon 0 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --agent enabled=1 \
  --ostype l26 --serial0 socket --vga serial0
qm set 1007 --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/ubuntu-26.04-server-cloudimg-amd64.img,discard=on
qm resize 1007 scsi0 30G
qm set 1007 --ide2 local-lvm:cloudinit --boot order=scsi0
qm set 1007 --ciuser ubuntu --sshkeys <public key> \
  --ipconfig0 ip=172.14.50.81/24,gw=172.14.50.90 --nameserver "172.14.50.90 8.8.8.8"
qm start 1007
```

I kept the parameters minimal, as the task asked. The host has little free RAM, so I gave the VM only 2 GB and added a 4 GB swap file inside it so the .NET build would not run out of memory.

The public key file at first had Windows line endings (CRLF). I removed them and regenerated the cloud-init disk.

### 3. Installing Docker

Inside the VM:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
sudo apt-get install -y ca-certificates curl git qemu-guest-agent
# official Docker repository (Ubuntu 26.04 "resolute" is supported)
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu resolute stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
```

### 4. HTTPS on 172.14.50.81:443

The local stack only works over HTTP on localhost, so I added three files without changing the original code:

- **`front/nginx.https.conf`**: nginx listens on 443 with TLS and redirects 80 to HTTPS. It proxies `/api`, `/uploads`, `/avatars`, `/swagger`, `/health` to the API and also `/hubs/*` with WebSocket upgrade for SignalR.
- **`deploy/compose.https.yaml`**: an override on top of `compose.local.yaml`:
  - builds the frontend with `NGINX_ENV=https` and `VITE_API_BASE_URL=https://172.14.50.81`;
  - sets `LocalStorage__BaseUrl=https://172.14.50.81`. Without it, video and avatar URLs would point to `http://localhost:8080`;
  - publishes ports 80/443. PostgreSQL and Redis are no longer exposed outside; the API (8080) and the RabbitMQ panel (15672) are bound to 127.0.0.1 only.
- **`deploy/gen-cert.sh`**: generates a self-signed certificate for the IP (with `subjectAltName=IP:172.14.50.81`). Let's Encrypt does not issue certificates for bare IP addresses.

### 5. Build and run

```bash
git clone https://github.com/ddoktor04-cmyk/SERV_tiktok_clone.git Tiktok_Clone
cd Tiktok_Clone
bash deploy/gen-cert.sh 172.14.50.81
F="-f compose.local.yaml -f deploy/compose.https.yaml"
# build images one at a time to save RAM on a small VM
for s in api video_processor frontend; do docker compose $F build $s; done
docker compose $F up -d
docker compose $F ps
```

Check:

```bash
curl -k https://172.14.50.81/health   # -> Healthy
```

I checked from another machine: `/health` → `Healthy`, the home page → 200, HTTP → 301 to HTTPS, login → 200, `/api/videos/fyp` returns the seeded videos with `https://172.14.50.81/uploads/...` URLs and the `.m3u8` files load. Ports 5432/6379/8080 are closed from outside.

Useful commands:

```bash
docker compose $F logs -f api video_processor   # logs
docker compose $F down                          # stop (data volumes are kept)
```

### Limitations

- The certificate is self-signed, so the browser shows a warning. Click "Advanced → Proceed".
- The app runs with `ASPNETCORE_ENVIRONMENT=Development`. Media is stored locally, not in Amazon S3, and no AWS keys are needed.
- Google sign-in and e-mail sending need your own Google OAuth and SMTP credentials, so they do not work in this lab setup. Email/password login and the seeded demo users (`back/Api/Helpers/Users.json`) work.
- Secrets (Proxmox password and similar) are not stored in this repository. `re.txt` is in `.gitignore`.

---

## Українська

> 🤖 **Розгортання виконав AI-агент: Claude Opus 5.5 (`claude-opus-5-5`) від Anthropic, у середовищі Claude Code.**
>
> Я — Claude, AI-модель компанії Anthropic. Тут я працював як агент у Claude Code, консольному інструменті Anthropic. Користувач поставив мені завдання звичайною українською мовою. Я виконав його сам через термінал: підключився до Proxmox по SSH, створив і налаштував VM, встановив Ubuntu і Docker, вивчив код проєкту, зібрав і запустив контейнери, перевірив, що все працює, і написав цей README. Там, де потрібні були рішення чи доступи (облікові дані, вільна IP-адреса), я питав користувача. Усе нижче написано від першої особи, від мене.

Цей репозиторій — копія проєкту TikTok Clone разом із файлами, які я додав, щоб розгорнути його на віртуальній машині Proxmox з HTTPS. Нижче я від свого імені описую все, що зробив.

### Результат

| Параметр | Значення |
| --- | --- |
| Хост Proxmox | `172.14.50.91` (PVE 9.1) |
| Віртуальна машина | VMID `1007`, ім'я `1007serStep` |
| Ресурси VM | 2 vCPU, 2 ГБ RAM (+4 ГБ swap-файл), диск 30 ГБ (local-lvm) |
| ОС | Ubuntu 26.04.1 LTS (cloud image) |
| Docker | Docker Engine 29.9 + Compose plugin v5.7 |
| Адреса застосунку | **<https://172.14.50.81>** (порт 443, з HTTP 80 перенаправляє на HTTPS) |
| Тестовий вхід | `string` / `String!1` (адмін, з тестових даних проєкту) |

### 1. Аналіз проєкту

Спершу я розібрав вихідний репозиторій:

- `front/`: React 19 + Vite. Збирається в Node і віддається через nginx. Адреса API задається під час збірки через `VITE_API_BASE_URL`.
- `back/Api`: API на .NET 10, порт 8080 (REST, SignalR-хаби `/hubs/*`, статика `/uploads`, `/avatars`). При старті сам застосовує міграції EF Core і створює тестових користувачів.
- `back/VideoProcessor`: .NET-сервіс, який обробляє відео через FFmpeg і отримує завдання з RabbitMQ.
- Інфраструктура: PostgreSQL, Redis, RabbitMQ.
- `compose.local.yaml` запускає все по HTTP на localhost. `compose.server.yaml` прив'язаний до продакшену авторів (домен duckdns, Let's Encrypt, Amazon S3), тому взяти його як є я не міг.

### 2. Створення VM у Proxmox

Я підключився до Proxmox по SSH і знайшов у сховищі ISO два образи Ubuntu. Обрав найновіший — `ubuntu-26.04-server-cloudimg-amd64.img`. Це cloud-образ, тому систему можна поставити без інтерактивного інсталятора і налаштувати через cloud-init:

```bash
qm create 1007 --name 1007serStep --memory 2048 --balloon 0 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --agent enabled=1 \
  --ostype l26 --serial0 socket --vga serial0
qm set 1007 --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/ubuntu-26.04-server-cloudimg-amd64.img,discard=on
qm resize 1007 scsi0 30G
qm set 1007 --ide2 local-lvm:cloudinit --boot order=scsi0
qm set 1007 --ciuser ubuntu --sshkeys <публічний ключ> \
  --ipconfig0 ip=172.14.50.81/24,gw=172.14.50.90 --nameserver "172.14.50.90 8.8.8.8"
qm start 1007
```

Параметри я взяв мінімальні, як було в завданні. Вільної пам'яті на хості мало, тому VM отримала лише 2 ГБ RAM, а всередині я додав swap-файл на 4 ГБ, щоб збірці .NET вистачило пам'яті.

У файлі публічного ключа спочатку були Windows-переноси рядків (CRLF). Я їх прибрав і перегенерував диск cloud-init.

### 3. Встановлення Docker

Усередині VM:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
sudo apt-get install -y ca-certificates curl git qemu-guest-agent
# офіційний репозиторій Docker (Ubuntu 26.04 "resolute" підтримується)
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu resolute stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
```

### 4. HTTPS на 172.14.50.81:443

Локальний варіант працює лише по HTTP на localhost, тому я додав три файли, не змінюючи оригінальний код:

- **`front/nginx.https.conf`**: nginx слухає 443 з TLS і перенаправляє 80 на HTTPS. Передає в API запити на `/api`, `/uploads`, `/avatars`, `/swagger`, `/health`, а також `/hubs/*` з підтримкою WebSocket для SignalR.
- **`deploy/compose.https.yaml`**: доповнення до `compose.local.yaml`:
  - збирає фронтенд з `NGINX_ENV=https` і `VITE_API_BASE_URL=https://172.14.50.81`;
  - задає `LocalStorage__BaseUrl=https://172.14.50.81`. Без цього посилання на відео та аватарки вели б на `http://localhost:8080`;
  - відкриває порти 80/443. PostgreSQL і Redis більше не доступні ззовні; API (8080) і панель RabbitMQ (15672) доступні лише з самої VM (127.0.0.1).
- **`deploy/gen-cert.sh`**: генерує самопідписаний сертифікат на IP (з `subjectAltName=IP:172.14.50.81`). Let's Encrypt не видає сертифікати на голу IP-адресу.

### 5. Збірка і запуск

```bash
git clone https://github.com/ddoktor04-cmyk/SERV_tiktok_clone.git Tiktok_Clone
cd Tiktok_Clone
bash deploy/gen-cert.sh 172.14.50.81
F="-f compose.local.yaml -f deploy/compose.https.yaml"
# збираю образи по одному, щоб маленькій VM вистачило RAM
for s in api video_processor frontend; do docker compose $F build $s; done
docker compose $F up -d
docker compose $F ps
```

Перевірка:

```bash
curl -k https://172.14.50.81/health   # -> Healthy
```

Я перевірив з іншої машини: `/health` → `Healthy`, головна сторінка → 200, HTTP → 301 на HTTPS, логін → 200, `/api/videos/fyp` повертає тестові відео з посиланнями `https://172.14.50.81/uploads/...`, і файли `.m3u8` завантажуються. Порти 5432/6379/8080 ззовні закриті.

Корисні команди:

```bash
docker compose $F logs -f api video_processor   # логи
docker compose $F down                          # зупинити (томи з даними зберігаються)
```

### Обмеження

- Сертифікат самопідписаний, тому браузер покаже попередження. Натисніть «Додатково → Перейти».
- Застосунок працює з `ASPNETCORE_ENVIRONMENT=Development`. Медіа зберігаються локально, а не в Amazon S3, і ключі AWS не потрібні.
- Вхід через Google і надсилання листів потребують власних ключів Google OAuth і SMTP, тому в цій лабораторній конфігурації вони не працюють. Вхід логіном і паролем та тестові користувачі (`back/Api/Helpers/Users.json`) працюють.
- Секрети (пароль від Proxmox тощо) у репозиторії не зберігаються. `re.txt` додано в `.gitignore`.
