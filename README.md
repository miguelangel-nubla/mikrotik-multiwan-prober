## Multi-WAN IP & Connectivity Checker

### Purpose

This tool allows you to verify the status and public IP address of specific internet connections (WANs) on a multi-homed router. While a standard "What's my IP" check only follows the default route, this tool forces the check through a specific gateway to ensure every path is functional.

### Why do I need a VPS? (Why not use `ifconfig.me`?)

You might wonder why you can't just point this script at `ifconfig.me` or `icanhazip.com`.

**The Problem: Routing Specificity**
To force traffic out of a specific WAN (Policy Based Routing), the router needs a **unique trigger** to distinguish the packets.

* **Public Services:** Almost all run on Port 80 or 443. If you try to route traffic to `ifconfig.me` (Port 80), the router can't easily distinguish a request intended for **WAN1** from a request intended for **WAN2** because the Destination IP and Port are identical.
* **CDN Issues:** Many services sit behind Cloudflare. Accessing them via a raw IP address (without a DNS Host header) often fails with 403 Errors, making them unsuitable for simple `fetch` commands.

The repository now includes a lightweight IP echo service written in Go (`main.go`) that listens on multiple ports (default is 2000-2010). This makes it easy to set up your own VPS without needing external dependencies like PHP or Python.

### How it works

1. **The VPS:** Runs the included Go IP echo service listening on multiple ports (e.g., 2001, 2002).
2. **The Router:** Uses "Mangle" rules to catch traffic destined for those specific ports and marks it for a specific routing table.
3. **The Script:** Connects via SSH and runs a native MikroTik script to fetch the IP using the specific port for that WAN.

---

### Complete Setup Example

This example assumes you have two WAN connections:

* **WAN1** (Gateway: `192.168.10.1`)
* **WAN2** (Gateway: `192.168.20.1`)
* **VPS IP:** `1.2.3.4`

#### 1. Create Routing Tables (RouterOS v7+)

Define the tables that will hold the isolated routes for each WAN.

```routeros
/routing table
add name=use_WAN1 fib
add name=use_WAN2 fib

```

#### 2. Add Routes

Add a default route for each table pointing to its respective gateway. This ensures traffic in the `use_WAN1` table actually leaves via WAN1.

```routeros
/ip route
add dst-address=0.0.0.0/0 gateway=192.168.10.1 routing-table=use_WAN1
add dst-address=0.0.0.0/0 gateway=192.168.20.1 routing-table=use_WAN2

```

#### 3. Define the Echo Target

Add your VPS IP to an address list in RouterOS.

```routeros
/ip firewall address-list
add address=1.2.3.4 list=IP_ECHO_TARGET
```

#### 4. Create Mangle Rules

These rules are the "switch." They match traffic based on the **Destination Port** and assign the Routing Mark.

```routeros
/ip firewall mangle
# Traffic to VPS Port 2001 -> Force to WAN1 Table
# (Matches the ports used in the Go service)
add chain=output dst-address-list=IP_ECHO_TARGET dst-port=2001 protocol=tcp \
    action=mark-routing new-routing-mark=use_WAN1 passthrough=yes

# Traffic to VPS Port 2002 -> Force to WAN2 Table
add chain=output dst-address-list=IP_ECHO_TARGET dst-port=2002 protocol=tcp \
    action=mark-routing new-routing-mark=use_WAN2 passthrough=yes

```

---

### Running the IP Echo Service (VPS)

You can run the service directly on your VPS using a pre-compiled binary, Docker, or by compiling it from source.

#### Download Binary (Recommended)
1. Go to the [Releases](https://github.com/miguelangel-nubla/mikrotik-multiwan-prober/releases) page.
2. Download and use the version for your OS and architecture (e.g., `linux_x86_64`).

#### Using Docker (Recommended)
You can run the official image from GitHub Container Registry:
```bash
docker run -d --name ip-echo -p 2000-2010:2000-2010 ghcr.io/miguelangel-nubla/mikrotik-multiwan-prober:latest
```

#### Compiling from Source
1. Build the binary:
   ```bash
   go build -o ip-echo main.go
   ```

#### Configuration (CLI Flags)
The Go service supports the following flags:
* `-addr`: Address to listen on (default: all interfaces).
* `-start-port`: Starting port range (default: `2000`).
* `-end-port`: Ending port range (default: `2010`).

Example:
```bash
./ip-echo -start-port 3000 -end-port 3010
```

#### Running on Boot (Ubuntu/systemd)
1. Copy the binary to `/usr/local/bin/ip-echo`.
2. Copy the included service file: `sudo cp ip-echo.service /etc/systemd/system/`
3. Reload systemd: `sudo systemctl daemon-reload`
4. Enable and start: `sudo systemctl enable --now ip-echo`

---

### Usage

Run the Bash wrapper from your monitoring system (Home Assistant, Linux box, etc).

**Syntax:** `./mikrotik_gateway_wan.sh <ROUTER_IP> <WAN_SUFFIX>`

```bash
# Check WAN 1 (This looks for the 'use_WAN1' routing mark)
./mikrotik_gateway_wan.sh 10.0.0.1 WAN1

# Check WAN 2 (This looks for the 'use_WAN2' routing mark)
./mikrotik_gateway_wan.sh 10.0.0.1 WAN2

```

### Results

* **Success:** Returns the public IP address (e.g., `203.0.113.5`) and exits with **Code 0**.
* **Failure:** Returns the error message (e.g., `timeout`, `no such item`) and exits with **Code 1**.

---

### Home Assistant Integration

Add this to your `configuration.yaml`. The sensors will display the IP address when online and become "Unavailable" if the connection fails.

```yaml
command_line:
  - sensor:
      name: "WAN1 Public IP"
      unique_id: mikro_wan1_ip
      command: "/config/scripts/mikrotik_gateway_wan.sh 10.0.0.1 WAN1"
      scan_interval: 60
      command_timeout: 15
      value_template: "{{ value }}"

  - sensor:
      name: "WAN2 Public IP"
      unique_id: mikro_wan2_ip
      command: "/config/scripts/mikrotik_gateway_wan.sh 10.0.0.1 WAN2"
      scan_interval: 60
      command_timeout: 15
      value_template: "{{ value }}"

```