#!/bin/bash

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
        else
            echo "Unsupported OS, please install jq manually."
            exit 1
        fi
    fi
}

# ---调用依赖检测函数---
check_dependency

# ---检查配置文件并生成---
config_file="./login_config.conf"

# 如果配置文件不存在，提示用户输入账号和密码
if [ ! -f "$config_file" ]; then
    echo "Configuration file not found. Please input your login details."
    read -p "Enter your account (DDDDD): " account
    read -sp "Enter your password (upass): " password
    echo ""
    # 保存账号密码到配置文件
    echo "DDDDD=$account" > "$config_file"
    echo "upass=$password" >> "$config_file"
    echo "Configuration file created successfully."
fi

# 读取配置文件中的账号和密码
source "$config_file"

# ---检查网络连接状态---
internetCheck=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connect.rom.miui.com/generate_204)

if [ "$internetCheck" == "204" ]; then
    logger "Connected to the internet. No need to login." && echo "Connected to the internet. No need to login."
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

# ---检查状态并尝试登录---
CheckStatusResponse=$(curl -s -G "http://172.16.2.2/drcom/chkstatus?callback=dr1003&jsVersion=4.1&v=630&lang=zh")
CheckStatusResponse=${CheckStatusResponse#*(}
CheckStatusResponse=${CheckStatusResponse%)*}

if [ -z "$CheckStatusResponse" ]; then
    logger "Error: Empty response. Please check your network connection." && echo "Error: Empty response. Please check your network connection."
    exit 1
else
    if [ "$(echo "$CheckStatusResponse" | jq '.result')" == 1 ]; then
        logger "User $(echo "$CheckStatusResponse" | jq '.AC') is already logged in." && echo "User $(echo "$CheckStatusResponse" | jq '.AC') is already logged in."
    else
        logger "Not logged in, attempting login..." && echo "Not logged in, attempting login..."
        loginResponse=$(curl -s -G "http://172.16.2.2/drcom/login?callback=dr1003&DDDDD=$DDDDD&upass=$upass&0MKKey=123456&R1=0&R2=&R3=1&R6=0&para=00&v6ip=&terminal_type=1&lang=zh-cn&jsVersion=4.1&v=10104&lang=zh")
        loginResponse=${loginResponse#*(}
        loginResponse=${loginResponse%)*}

        if [ "$(echo "$loginResponse" | jq '.result')" == 1 ]; then
            logger "User $(echo "$loginResponse" | jq '.uid') logged in successfully." && echo "User $(echo "$loginResponse" | jq '.uid') logged in successfully."
        else
            logger "Login failed. Please check your username and password." && echo "Login failed. Please check your username and password."
        fi
    fi
fi
