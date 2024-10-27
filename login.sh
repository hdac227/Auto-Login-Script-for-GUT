#!/bin/sh

CONFIG_FILE="./login_config.conf"
LOG_FILE="./login.log"

# ---日志记录函数---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}
# ---检测是否安装了curl和jq---
check_dependency() {
    if ! command -v curl &> /dev/null; then
        log "curl not found, installing..."
        if [ -f /etc/opkg.conf ]; then
            opkg update && opkg install curl
        else
            log "Unsupported OS, please install curl manually."
            exit 1
        fi
    fi

    if ! command -v jq &> /dev/null; then
        log "jq not found, installing..."
        if [ -f /etc/opkg.conf ]; then
            opkg update && opkg install jq
        else
            log "Unsupported OS, please install jq manually."
            exit 1
        fi
    fi
}

# ---调用依赖检测函数---
check_dependency

# 读取或生成配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found. Creating a new one..."
    read -p "Enter account: " account
    read -p "Enter password: " password
    read -p "Select Network Type: Campus Network (1), China Telecom (2), China Mobile (3), China Unicom (4): " R3
    let R3--

    if [[ "$R3" -lt 0 || "$R3" -gt 3 ]]; then
        echo "Invalid Network Type. Must be between 1 and 4."
        exit 1
    fi

    echo "account=$account" > "$CONFIG_FILE"
    echo "password=$password" >> "$CONFIG_FILE"
    echo "R3=$R3" >> "$CONFIG_FILE"
else
    source "$CONFIG_FILE"
    if [ -z "$account" ] || [ -z "$password" ] || [ -z "$R3" ]; then
        echo "Configuration file is incomplete. Overwriting it with new values..."
        read -p "Enter account: " account
        read -p "Enter password: " password
        read -p "Select Network Type: Campus Network (1), China Telecom (2), China Mobile (3), China Unicom (4): " R3
        let R3--

        if [[ "$R3" -lt 0 || "$R3" -gt 3 ]]; then
            echo "Invalid Network Type. Must be between 1 and 4."
            exit 1
        fi

        echo "account=$account" > "$CONFIG_FILE"
        echo "password=$password" >> "$CONFIG_FILE"
        echo "R3=$R3" >> "$CONFIG_FILE"
    fi
fi

# 生成随机数作为v值
generate_random_v() {
    echo $((RANDOM % 9001 + 1000))
}

# ---检查网络连接状态---
check_network() {
	local retries=0
	while [ $retries -lt 10 ]; do 
		internetCheck=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connect.rom.miui.com/generate_204)
		if [ "$internetCheck" == "204" ]; then
			log "Already connected to the internet. No need to login."
			exit 0
		elif [ "$internetCheck" == "200" ]; then
			log "Network available but not logged in. Attempting login..."
			return 0
		elif [ -n "$internetCheck" ]; then
			log "Redirect detected, proceeding to login..."
			return 0
		else
			log "No network connection or unable to access login page."
			sleep 60
            retries=$((retries + 1))
		fi
    done
}

# ---解绑mac并登出函数---
unbind_and_logout() {
    random_v=$(generate_random_v)

    # 获取当前用户的mac和ip
    chkstatusResponse=$(curl -s -G "http://172.16.2.2/drcom/chkstatus?callback=dr1002&jsVersion=4.1&v=$random_v&lang=zh")
    chkstatusResponse=${chkstatusResponse#*(}
    chkstatusResponse=${chkstatusResponse%)*}

    wlan_user_mac=$(echo "$chkstatusResponse" | jq -r '.ss4')
    wlan_user_ip=$(echo "$chkstatusResponse" | jq -r '.ss5')

    if [ -n "$wlan_user_mac" ] && [ -n "$wlan_user_ip" ]; then
        # 发起解绑mac请求
        unbindResponse=$(curl -s -G "http://172.16.2.2/eportal/portal/mac/unbind?callback=dr1003&user_account=$account&wlan_user_mac=$wlan_user_mac&wlan_user_ip=$wlan_user_ip&jsVersion=4.1&v=$random_v&lang=zh")
        log "MAC unbound response: $unbindResponse"

        # 发送登出请求
        logoutResponse=$(curl -s -G "http://172.16.2.2/drcom/logout?callback=dr1004&jsVersion=4.1&v=$random_v&lang=zh")
        log "Logout response: $logoutResponse"
    else
        log "Error: Could not retrieve MAC or IP for unbinding."
    fi
}

# ---登录函数---
login() {
    local attempt=1
    while [ $attempt -le 5 ]; do
        log "Login attempt $attempt..."

        random_v=$(generate_random_v)
        checkStatusResponse=$(curl -s -G "http://172.16.2.2/drcom/chkstatus?callback=dr1003&jsVersion=4.1&v=$random_v&lang=zh")
        checkStatusResponse=${checkStatusResponse#*(}
        checkStatusResponse=${checkStatusResponse%)*}

        if [ "$(echo "$checkStatusResponse" | jq '.result')" == 1 ]; then
            log "Already logged in as $(echo "$checkStatusResponse" | jq '.AC')."
            return 0
        else
            loginResponse=$(curl -s -G "http://172.16.2.2/drcom/login?callback=dr1003&DDDDD=$account&upass=$password&0MKKey=123456&R1=0&R2=&R3=$R3&R6=0&para=00&v6ip=&terminal_type=1&lang=zh-cn&jsVersion=4.1&v=$random_v&lang=zh")
            loginResponse=${loginResponse#*(}
            loginResponse=${loginResponse%)*}

            if [ "$(echo "$loginResponse" | jq '.result')" == 1 ]; then
                log "Login successful for user $(echo "$loginResponse" | jq '.uid')."
                return 0
            else
                log "Login failed. Retrying in 5 minutes..."
                unbind_and_logout
                sleep 300
                attempt=$((attempt + 1))
            fi
        fi
    done

    log "Reached maximum login attempts. Terminating script."
    exit 1
}

# ---启动检测并登录---
check_network
login
