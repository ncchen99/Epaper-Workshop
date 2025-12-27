# REST API Documentation for E-Paper Workshop

This document describes the REST API endpoints available on the Arduino Nano ESP32 E-Paper device.

**Base URL**: `http://epaper.local` or `http://<Device_IP>`

## Endpoints

### 1. Show Image

Displays an image from the local storage (Slots 1, 2, or 3).

*   **URL**: `/api/show`
*   **Method**: `GET`
*   **Query Parameters**:
    *   `slot` (required): The slot number (`1`, `2`, or `3`).
*   **Response**:
    *   `200 OK`: "OK" - Request accepted and execution started.
    *   `400 Bad Request`: "Invalid Slot" or "Missing Slot".

**Example**:
Display image from Slot 2.
```bash
curl "http://epaper.local/api/show?slot=2"
```

### 2. Update and Show Image

Downloads the latest image for the specified slot from the cloud, saves it, and then displays it.

*   **URL**: `/api/update`
*   **Method**: `GET`
*   **Query Parameters**:
    *   `slot` (required): The slot number (`1`, `2`, or `3`).
*   **Response**:
    *   `200 OK`: "OK" - Request accepted and execution started.
    *   `400 Bad Request`: "Invalid Slot" or "Missing Slot".

**Example**:
Update and display image for Slot 1.
```bash
curl "http://epaper.local/api/update?slot=1"
```

## Control Interface

A built-in web control interface is available at the root URL:
`http://epaper.local/`
