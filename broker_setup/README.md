# MQTT Broker 部署指南

本文件說明如何在 Desktop 電腦上安裝與啟動 Mosquitto MQTT Broker，供 E-Paper Workshop 第一階段（區域網路 Demo）使用。

## 前置需求

- Desktop 電腦（macOS / Windows / Linux）
- 與手機、ESP32 裝置連接至相同的 Wi-Fi 區域網路

---

## 安裝 Mosquitto

### macOS

```bash
brew install mosquitto
```

### Windows

1. 至 [Mosquitto 官網](https://mosquitto.org/download/) 下載 Windows 安裝包
2. 執行安裝精靈並完成安裝
3. Mosquitto 預設安裝在 `C:\Program Files\mosquitto\`

### Linux (Ubuntu / Debian)

```bash
sudo apt update
sudo apt install mosquitto mosquitto-clients
```

---

## 設定

將本目錄下的 `mosquitto.conf` 複製到 Mosquitto 設定目錄。

### macOS (Homebrew)

```bash
cp mosquitto.conf /opt/homebrew/etc/mosquitto/mosquitto.conf
```

### Windows

```cmd
copy mosquitto.conf "C:\Program Files\mosquitto\mosquitto.conf"
```

### Linux

```bash
sudo cp mosquitto.conf /etc/mosquitto/mosquitto.conf
```

---

## 啟動 Broker

### macOS

```bash
# 前景執行（可看到即時 log）
mosquitto -c /opt/homebrew/etc/mosquitto/mosquitto.conf -v

# 或以 Homebrew 背景服務啟動
brew services start mosquitto
```

### Windows

```cmd
cd "C:\Program Files\mosquitto"
mosquitto.exe -c mosquitto.conf -v
```

### Linux

```bash
# 前景執行
mosquitto -c /etc/mosquitto/mosquitto.conf -v

# 2026-04-05 測試
mosquitto -c /Users/ncchen/Downloads/Epaper-Workshop/broker_setup/mosquitto.conf -v

# 或使用 systemd
sudo systemctl start mosquitto
sudo systemctl enable mosquitto
```

---

## 取得電腦的區網 IP

此 IP 將設定於 Flutter App 和 ESP32 Firmware 中作為 Broker 連線位址。

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

找到類似 `192.168.x.x` 或 `10.x.x.x` 的 IP 位址。

---

## 防火牆設定

確保作業系統防火牆允許 TCP Port **1883** 的入站連線。

### macOS

macOS 通常會在首次連線時跳出防火牆提示，選擇「允許」即可。

### Windows

```cmd
netsh advfirewall firewall add rule name="Mosquitto MQTT" dir=in action=allow protocol=TCP localport=1883
```

### Linux (ufw)

```bash
sudo ufw allow 1883/tcp
```

---

## 驗證連線

打開兩個終端視窗進行測試：

### 終端 1：訂閱所有裝置 Topic

```bash
mosquitto_sub -h localhost -t "devices/#" -v
```

### 終端 2：發送測試訊息

```bash
mosquitto_pub -h localhost -t "devices/AABBCC112233/cmd" -m '{"action":"update","url":"https://example.com/test.jpg"}'
```

如果終端 1 收到訊息，表示 Broker 運作正常 ✅

---

## 常見問題

### Q: Broker 啟動失敗，顯示 port 已被佔用

```bash
# 檢查是否有其他程式佔用 1883
lsof -i :1883    # macOS / Linux
netstat -an | findstr 1883  # Windows
```

### Q: ESP32 或手機無法連線

1. 確認所有裝置連上相同的 Wi-Fi AP
2. 確認防火牆已開放 Port 1883
3. 確認使用的 IP 正確（不是 127.0.0.1）
4. 使用 `mosquitto_sub` 在本機測試確認 Broker 正常運作

---

## 2026-04-04 事件紀錄：Flutter 無法透過 mDNS 連上 Broker

### 症狀

- Flutter 設定 Broker 為 `epaper-broker.local`，但 App 連線失敗。
- 本機測試顯示：
	- `ping epaper-broker.local` 無法解析（Unknown host）
	- `nc -vz epaper-broker.local 1883` 出現 `getaddrinfo` 錯誤

### 根因

- macOS 的 `LocalHostName` 不是 `epaper-broker`，因此 `epaper-broker.local` 並未在 Bonjour/mDNS 正確廣播。
- App 端使用 `.local` 主機名時，DNS 解析層先失敗，導致 MQTT 連線失敗。

### 修復步驟（macOS Broker 主機）

1. 設定本機 mDNS 主機名：

```bash
scutil --set LocalHostName epaper-broker
```

2. 驗證主機名已套用：

```bash
scutil --get LocalHostName
```

3. 驗證 mDNS 解析：

```bash
dns-sd -G v4v6 epaper-broker.local
```

4. 驗證 MQTT 埠可達：

```bash
nc -vz -G 2 epaper-broker.local 1883
```

### 修復後驗證結果

- `epaper-broker.local` 可解析到區網位址（本次為 `172.20.10.9`）。
- `nc` 對 `1883` 最終可連通（可能先看到 IPv6 refused，再由 IPv4 成功，屬常見情況）。

### Flutter 端已做的保護（避免單點失敗）

- 已加入 mDNS 解析 timeout 與 DNS fallback。
- 已加入 Broker 候選位址機制（主 mDNS + 可選 fallback host）。
- 可在執行時指定 fallback：

```bash
flutter run --dart-define=MQTT_BROKER_FALLBACK_HOST=192.168.x.x
```

### 預防建議

1. 每次工作坊開始前，先執行一次 `dns-sd -G v4v6 epaper-broker.local`。
2. 若 mDNS 不穩，現場先用 `--dart-define=MQTT_BROKER_FALLBACK_HOST=...` 保障可用性。
3. 若要跨平台（特別是 Windows）穩定使用 `.local`，需確認 Bonjour 服務已安裝且可運作。
