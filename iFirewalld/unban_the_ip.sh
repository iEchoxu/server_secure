#!/bin/bash
# desc: 解禁 ip(即：黑名单数据删除操作)
# author: echoxu
# 功能:
#       1. 命令行中添加要解禁的 ip,支持批量操作
#       2: 可解禁指定文件里的 ip，支持批量操作

. lib/common
. lib/firewall
. lib/nginx
. lib/blacklist


args_arr=()


# 组成非第一个参数外的所有参数列表
analysis_args(){ 
    args=$@

    for arg in $args
    do
        args_arr[${#args_arr[*]}]=${arg}
    done

    unset args_arr[0]  # 删除第一个元素,即传入的 flag 的值
}


# 重启 nginx/firewalld 的 handler 函数
relaod_handler(){
    block_ip_type=$(get_section_value_from_config_path block_ip_type)
    code=$?
    print_return_code_message_of_get_section_path $code

    case "$block_ip_type" in
    firewalld)
        block_ip_type=firewalld_reload
        ;;
    nginx)
        block_ip_type=reload_nginx
        ;;
    esac

    echo $block_ip_type


}


# 统计返回值,当返回值为 0 的个数大于 1 时才能重启防火墙
# 也可以通过判断 blacklist 或者 blockip.conf 文件是否被修改来决定是否重启
reload_of_block_ip_type(){
    succeed_code_count=0
    for i in `cat /tmp/add_ip_to_blacklist_return_code`
    do
        if [ $i -eq 0 ];then
            let succeed_code_count++
        fi

    done

    if [ $succeed_code_count -gt 0 ];then
        reload_res=$(relaod_handler)
        $reload_res
    fi
    
}


# 将操作记录到日志中
record_logs_of_unban_ip(){
    to_log=$1
    log_path=$2

    echo "$(date +'%F-%T') 解禁ip: $to_log " >> $log_path
}


# handler 函数
get_block_ip_type_of_unban_ip_handler(){
    block_ip_type_input=$1

    case "$block_ip_type_input" in
    firewalld)
        block_ip_type_input=firewall_op_with_remove
        ;;
    nginx)
        block_ip_type_input=nginx_record_remove
        ;;
    esac

    echo $block_ip_type_input
}


# 从命令行中解封一个或多个 ip
unban_the_ip(){
    for arg in ${args_arr[*]}
    do
        is_ip_result=$(isip_from_input $arg)
        code=$?
        if [ $code != 0 ];then
            err_code $code "$arg 不符合 ip 格式，请确认后再操作..."
            echo $code >> /tmp/add_ip_to_blacklist_return_code
            continue
        else
            arg=$is_ip_result
        fi

        if [ "$block_ip_type" = "firewalld" ];then
            delete_ip_from_blacklist $arg
            code=$?
            if [ $code -eq 144 ];then
                err_code $code "IP: $arg 在黑名单文件中不存在..."
                continue
            fi
        fi

        $block_ip_type_result $arg
        code=$?
        echo $code >> /tmp/add_ip_to_blacklist_return_code
        if [ $code = 0 ];then
            record_logs_of_unban_ip $arg $log_path
        fi
      
    done

}


# 批量解封 ip: 从文件中获取待解禁的 ip
unban_the_ip_from_file(){
    unban_ip_file_path=$1

    real_path=$(get_real_path $unban_ip_file_path)
    is_file_res=$(vaild_is_path_from_input $real_path)
    code=$?
    if [ $code != 0 ];then
        print_message_of_vaild_is_path_from_input $code $real_path
    else
        unban_ip_file_path=$is_file_res
    fi
    
    for ip_from_file in `cat $unban_ip_file_path`
    do
        is_ip_result=$(isip_from_input $ip_from_file)
        code=$?
        if [ $code != 0 ];then
            err_code $code "$ip_from_file 不符合 ip 格式，请重新输入..."
            echo $code >> /tmp/add_ip_to_blacklist_return_code
            continue
        fi

        if [ "$block_ip_type" = "firewalld" ];then
            delete_ip_from_blacklist $ip_from_file
            code=$?
            if [ $code -eq 144 ];then
                err_code $code "IP: $ip_from_file 在黑名单文件中不存在..."
                continue
            fi
        fi

        $block_ip_type_result $ip_from_file
        code=$?
        echo $code >> /tmp/add_ip_to_blacklist_return_code
        if [ $code = 0 ];then
            record_logs_of_unban_ip $ip_from_file $log_path
        fi
    done
       
}


# 路由函数
unban_the_ip_router(){
    args=$@
    flag=$1
    args_number=$#
    to_unban_filepath=$2

    # 清空返回值
    cat /dev/null > /tmp/add_ip_to_blacklist_return_code

    # 获取 封禁/解禁 ip 的方式
    block_ip_type=$(get_section_value_from_config_path block_ip_type)
    code=$?
    print_return_code_message_of_get_section_path $code

    block_ip_type_result=$(get_block_ip_type_of_unban_ip_handler $block_ip_type)


    # 防火墙状态检查
    if [[ $block_ip_type_result == "firewall_op_with_remove" ]];then
        firewall_status=$(check_firewall_status)
        code=$?
        print_message_of_check_firewall_status $code
    fi

    # 获取日志文件存储路径（获取一次即可,所以写在这里）
    log_path=$(get_section_value_from_config_path server_secure_log_path)
    code=$?
    print_return_code_message_of_get_section_path $code

    # 判断参数
    case "$flag" in
    -u)
        # 指定这个 flag 时，总参数个数不能小于 2
        if [ $args_number -lt 2 ];then
            echo -e "${Error}: 总参数个数不能小于 2"
            exit 1
        fi

        analysis_args $@
        unban_the_ip
        ;;
    -f)
        # 指定这个 flag 时,总参数个数不能大于 2
        if [[ $args_number -gt 2 || $args_number -lt 2 ]];then
            echo -e "${Error}: 总参数个数不能小于 2 且不能大于 3"
            exit 1
        fi

        unban_the_ip_from_file $to_unban_filepath
        ;;
    *)
        echo -e "${Error}: Usage: $0 -u 单个或多个 ip|-f 文件路径"
        echo -e "${Info}: -u: 解封单个或多个 ip"
        echo -e "${Info}: -f: 从指定的文件里读取 ip 并解封"
        exit 1
    ;;
    esac

    reload_of_block_ip_type
}


unban_the_ip_router $@