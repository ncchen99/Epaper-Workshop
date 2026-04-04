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
