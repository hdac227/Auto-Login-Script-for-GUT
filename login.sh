#!/bin/bash

CONFIG_FILE="./login_config.conf"

# ---检测是否安装了curl和jq---
check_dependency() {
    # 检查是否安装了curl
    if ! command -v curl &> /dev/null; then
        echo "curl not found, installing..."
        # 根据操作系统类型安装依赖
        if [ -f /etc/debian_version ]; then
            sudo apt update && sudo apt install -y curl
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y curl
        elif [ -f /etc/opkg.conf ]; then
            sudo opkg update
            sudo opkg install curl
        else
            echo "Unsupported OS, please install curl manually."
            exit 1
        fi
    fi

    # 检查是否安装了jq
    if ! command -v jq &> /dev/null; then
        echo "jq not found, installing..."
        if [ -f /etc/debian_version ]; then
            sudo apt update && sudo apt install -y jq
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y jq
        elif [ -f /etc/opkg.conf ]; then
            sudo opkg update
            sudo opkg install jq
        else
            echo "Unsupported OS, please install jq manually."
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

    #实际输入的值会比R3多1
    let R3--

    if [[ "$R3" -lt 0 || "$R3" -gt 3 ]]; then
        echo "Invalid Network Type. Must be between 1 and 4."
        exit 1
    fi

    echo "account=$account" > "$CONFIG_FILE"
    echo "password=$password" >> "$CONFIG_FILE"
    echo "R3=$R3" >> "$CONFIG_FILE"

    echo "Configuration file created: $CONFIG_FILE"
else
    echo "Loading configuration from $CONFIG_FILE..."
    source "$CONFIG_FILE"
    
    # 如果配置文件缺少参数，提示用户补全
    if [ -z "$account" ] || [ -z "$password" ] || [ -z "$R3" ]; then
        echo "Configuration file is incomplete. Overwriting it with new values..."
        
        read -p "Enter account: " account
        read -p "Enter password: " password
        read -p "Select Network Type: Campus Network (1), China Telecom (2), China Mobile (3), China Unicom (4): " R3

        #实际输入的值会比R3多1
        let R3--

        if [[ "$R3" -lt 0 || "$R3" -gt 3 ]]; then
            echo "Invalid Network Type. Must be between 1 and 4."
            exit 1
        fi

        echo "account=$account" > "$CONFIG_FILE"
        echo "password=$password" >> "$CONFIG_FILE"
        echo "R3=$R3" >> "$CONFIG_FILE"

        echo "Configuration updated: $CONFIG_FILE"
    fi
fi
# 读取配置文件中的账号和密码
CONFIG_FILE="./login_config.conf"

# ---检查网络连接状态---
internetCheck=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connect.rom.miui.com/generate_204)

if [ "$internetCheck" == "204" ]; then
    logger "Already connected to the internet. No need to login." && echo "Already connected to the internet. No need to login."
    exit 0
elif [ "$internetCheck" == "200" ]; then
    logger "Network available but not logged in. Attempting login..." && echo "Network available but not logged in. Attempting login..."
else
    redirectCheck=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 5 http://connect.rom.miui.com/generate_204)
    if [ -n "$redirectCheck" ]; then
        logger "Redirect detected, proceeding to login..." && echo "Redirect detected, proceeding to login..."
    else
        logger "No network connection or unable to access login page." && echo "No network connection or unable to access login page."
        exit 1
    fi
fi

# 生成随机数作为v值
random_v=$((RANDOM % 9001 + 1000))

# ---检查状态并尝试登录---
checkStatusResponse=$(curl -s -G "http://172.16.2.2/drcom/chkstatus?callback=dr1003&jsVersion=4.1&v=$random_v&lang=zh")
checkStatusResponse=${checkStatusResponse#*(}
checkStatusResponse=${checkStatusResponse%)*}

if [ -z "$checkStatusResponse" ]; then
    echo "Error: Empty response. Check network connection."
    exit 1
else
    if [ "$(echo "$checkStatusResponse" | jq '.result')" == 1 ]; then
        echo "User $(echo "$checkStatusResponse" | jq '.AC') is already logged in."
    else
        echo "Not logged in. Attempting to log in..."
        
        # 发起登录请求
        loginResponse=$(curl -s -G "http://172.16.2.2/drcom/login?callback=dr1003&DDDDD=$account&upass=$password&0MKKey=123456&R1=0&R2=&R3=$R3&R6=0&para=00&v6ip=&terminal_type=1&lang=zh-cn&jsVersion=4.1&v=$random_v&lang=zh")
        loginResponse=${loginResponse#*(}
        loginResponse=${loginResponse%)*}

        if [ "$(echo "$loginResponse" | jq '.result')" == 1 ]; then
            echo "User $(echo "$loginResponse" | jq '.uid') has successfully logged in."
        else
            echo "Login failed. Please check account and password."
        fi
    fi
fi
