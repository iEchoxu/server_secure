#!/bin/bash
# desc: ip 白名单
# author: echoxu
# 功能:
#       1. add: 将 ip 添加进白名单，支持批量操作
#       2. remove: 从白名单中删除 ip，支持批量操作
#       3. list: 获取白名单列表
# todo: 批量操作 (ps: 不想写了,传参和返回值写的太痛苦了)

. lib/common

add(){
    to_add_ip=$1

    isip_res=$(isip_from_input $to_add_ip)
    code=$?
    if [ $code != 0 ];then
        err_code $code "$to_add_ip 不符合 ip 格式，请重新输入..."
        return 205
    fi

    isipexist_in_file $whitelist_file $to_add_ip
    code=$?
    if [ $code -eq 200 ];then
        err_code $code "$to_add_ip 在白名单中已存在，请勿重复添加..."
        return  200
    fi

    echo $to_add_ip >> $whitelist_file

    echo -e "${Succeed}: 已添加白名单 ip: $to_add_ip"

    echo "$(date +'%F-%T') 已添加白名单ip: $to_add_ip " >> $log_path
}


remove(){
    to_remove_ip=$1

    isip_res=$(isip_from_input $to_remove_ip)
    code=$?
    if [ $code != 0 ];then
        err_code $code "$to_remove_ip 不符合 ip 格式，请重新输入..."
        return 205
    fi

    isipexist_in_file $whitelist_file $to_remove_ip
    code=$?
    if [ $code -eq 144 ];then
        err_code $code "$to_remove_ip 在白名单中不存在..."
        return  144
    fi

    sed -i '/^'"${to_remove_ip}"'$/d' $whitelist_file

    echo -e "${Succeed}: 已删除白名单 ip: $to_remove_ip"

    echo "$(date +'%F-%T') 已删除白名单ip: $to_remove_ip " >> $log_path
}


get(){
    for whitelist in `cat $whitelist_file`
    do
        echo $whitelist
    done
}


white_list_router(){
    flags=$1

    log_path=$(get_section_value_from_config_path server_secure_log_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $log_path ];then
        err_code 104 "操作日志记录文件: $log_path 不存在..."
        exit 1
    fi

    whitelist_file=$(get_section_value_from_config_path whitelist_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $whitelist_file ];then
        err_code 104 "白名单文件: $whitelist_file 不存在..."
        exit 1
    fi

    case "$flags" in
    add|a)
        add $2
        ;;
    remove|r)
        remove $2
        ;;
    list|l)
        get
        ;;
    *)
        echo "Usage: $0 {add|remove|list}"
        return 1
    ;;
    esac
}


white_list_router $1 $2