# MQTT Broker 部署指南（Mosquitto）

本文件說明如何在桌機（macOS / Windows / Linux）安裝與啟動 Mosquitto，供 InkSync 使用。

## 前置需求

- 一台 Desktop / Laptop（可長時間開機）
- 與手機、ESP32 連到同一個 Wi-Fi 區域網路
- 開放 TCP 1883 入站

## 本專案使用的 MQTT Topic

- 指令 Topic：devices/{MAC}/cmd
- 狀態 Topic：devices/{MAC}/state

測試指令範例：

```bash
mosquitto_pub -h localhost -t "devices/AABBCC112233/cmd" -m '{"action":"update","url":"https://example.com/test.jpg","slot":1}'
```

## 安裝 Mosquitto

### macOS

```bash
brew install mosquitto
```

### Windows

1. 到 https://mosquitto.org/download/ 下載安裝程式
2. 完成安裝（預設路徑通常是 C:\Program Files\mosquitto）

### Linux（Ubuntu / Debian）

```bash
sudo apt update
sudo apt install mosquitto mosquitto-clients
```

## 套用設定檔

將本資料夾的 mosquitto.conf 複製到系統設定路徑。

### macOS（Apple Silicon）

```bash
cp mosquitto.conf /opt/homebrew/etc/mosquitto/mosquitto.conf
```

### macOS（Intel）

```bash
cp mosquitto.conf /usr/local/etc/mosquitto/mosquitto.conf
```

### Windows

```cmd
copy mosquitto.conf "C:\Program Files\mosquitto\mosquitto.conf"
```

### Linux

```bash
sudo cp mosquitto.conf /etc/mosquitto/mosquitto.conf
```

## 啟動 Broker

### macOS

前景除錯：

```bash
mosquitto -c mosquitto.conf -v
```

背景服務：

```bash
brew services start mosquitto
brew services restart mosquitto
brew services stop mosquitto
```

### Windows

```cmd
cd "C:\Program Files\mosquitto"
mosquitto.exe -c mosquitto.conf -v
```

### Linux

前景除錯：

```bash
mosquitto -c /etc/mosquitto/mosquitto.conf -v
```

使用 systemd：

```bash
sudo systemctl start mosquitto
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto
sudo systemctl status mosquitto
```

## 取得 Broker 區網 IP

### macOS

```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### Windows

```cmd
ipconfig
```

### Linux

```bash
ip a | grep "inet " | grep -v 127.0.0.1
```

## 防火牆設定

請允許 TCP 1883 入站。

### Windows

```cmd
netsh advfirewall firewall add rule name="Mosquitto MQTT" dir=in action=allow protocol=TCP localport=1883
```

### Linux（ufw）

```bash
sudo ufw allow 1883/tcp
```

## 驗證 Broker

終端 1：

```bash
mosquitto_sub -h localhost -t "devices/#" -v
```

終端 2：

```bash
mosquitto_pub -h localhost -t "devices/AABBCC112233/cmd" -m '{"action":"show","slot":1}'
```

若終端 1 有收到訊息，表示 Broker 正常。

## 伺服器是否正確建立：快速檢查清單

請依序確認以下 6 點：

1. Mosquitto 服務有啟動
- macOS: `brew services list | grep mosquitto`
- Linux: `sudo systemctl status mosquitto`

2. Port 1883 正在監聽
- macOS / Linux: `lsof -i :1883`
- Windows: `netstat -an | findstr 1883`

3. 本機 publish/subscribe 可互通
- 一個終端跑 `mosquitto_sub -h localhost -t "devices/#" -v`
- 另一個終端跑 `mosquitto_pub -h localhost -t "devices/test/cmd" -m '{"action":"show","slot":1}'`

4. 區網其他裝置可以連到 Broker IP
- 手機與 ESP32 必須和 Broker 在同一個 Wi-Fi
- 不要使用 `127.0.0.1` 作為遠端裝置連線目標

5. 防火牆已開放 1883
- Windows 防火牆規則已建立
- Linux ufw 已 allow 1883/tcp

6. mDNS 名稱可被解析（若你使用 epaper-broker.local）
- macOS: `dns-sd -G v4v6 epaper-broker.local`
- 若解析不到，先改用 Broker 區網 IP 測試

## 除錯流程（建議照順序）

### Step 1: 先用前景模式看即時 log

在 broker 主機執行：

```bash
mosquitto -c mosquitto.conf -v
```

若這一步就失敗，先不要往 App/ESP32 查，先修 broker 設定與埠口衝突。

### Step 2: 再切到背景服務模式

macOS（brew services）：

```bash
brew services restart mosquitto
brew services list | grep mosquitto
```

Linux（systemctl）：

```bash
sudo systemctl restart mosquitto
sudo systemctl status mosquitto
sudo systemctl is-enabled mosquitto
```

若 Linux 服務啟動失敗，查看詳細 log：

```bash
sudo journalctl -u mosquitto -n 100 --no-pager
sudo journalctl -u mosquitto -f
```

### Step 3: 驗證 topic 與 payload

請確認你發送的 topic 與裝置訂閱一致：
- 指令：`devices/{MAC}/cmd`
- 狀態：`devices/{MAC}/state`

常見錯誤：
- MAC 大小寫或分隔符不一致（建議統一 12 碼大寫，例如 `AABBCC112233`）
- payload key 拼錯（例如 `url` / `slot` / `action`）

### Step 4: mDNS 專項除錯

若 `epaper-broker.local` 不穩：

1. 設定主機 mDNS 名稱（macOS）：
```bash
scutil --set LocalHostName epaper-broker
scutil --get LocalHostName
```

2. 驗證名稱可解析：
```bash
dns-sd -G v4v6 epaper-broker.local
```

3. 驗證埠可達：
```bash
nc -vz -G 2 epaper-broker.local 1883
```

4. 若現場網路對 mDNS 不友善，Flutter 請改用 fallback host：
```bash
flutter run --dart-define=MQTT_BROKER_FALLBACK_HOST=192.168.x.x
```

## 常見問題

### 1) Port 1883 被占用

```bash
lsof -i :1883
```

Windows：

```cmd
netstat -an | findstr 1883
```

### 2) App 無法用 epaper-broker.local 連線

可能是 mDNS 主機名未正確廣播。可先設定：

```bash
scutil --set LocalHostName epaper-broker
scutil --get LocalHostName
dns-sd -G v4v6 epaper-broker.local
nc -vz -G 2 epaper-broker.local 1883
```

若現場 mDNS 不穩，Flutter 可加 fallback host：

```bash
flutter run --dart-define=MQTT_BROKER_FALLBACK_HOST=192.168.x.x
```
