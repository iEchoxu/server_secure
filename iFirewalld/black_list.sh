#!/bin/bash
# desc: ip 黑名单的路由函数,其核心在 lib/blacklist 中
# author: echoxu
# todo: 异步执行，提高运行效率
# todo: 改用 sqlite3 作为数据存储
# todo: 相比于封禁 ip，更应该构建强劲的 web 防火墙, 用 openresty 代替 nginx

. lib/blacklist
. lib/common
. lib/firewall
. lib/nginx


args_arry=()

analysis_args(){ 
    args=$@

    for arg in $args
    do
        args_arr[${#args_arr[*]}]=${arg}
    done  
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


# 添加黑名单数据的路由函数
add_ip_to_blacklist_router(){
    args_number=$#
    second_flag=$2
    input_filepath=$3

    # 清空返回值
    cat /dev/null > /tmp/add_ip_to_blacklist_return_code

    case "$second_flag" in
    -i)
        analysis_args $@

        if [ $args_number -lt 3 ];then
            echo -e "${Error}: 总参数个数不能小于 3"
            exit 1
        fi

        # 设置切片长度，排除了前两个元素
        not_flags_len=`expr ${#args_arr[*]} - 2`

        # 数组切片：打印第三个元素到末尾的所有元素
        for ip in "${args_arr[@]:2:$not_flags_len}"
        do 
            add_ip_to_blacklist_with_input $ip
            return_code=$?
            # 记录返回值用于判断是否重启防护墙
            echo $return_code >> /tmp/add_ip_to_blacklist_return_code
            if [ $return_code != 0 ];then  
                continue
            fi
        done
        
        ;;
    -f)
        if [[ $args_number -gt 3 || $args_number -lt 3 ]];then
            echo -e "${Error}: 总参数个数不能小于 2 且不能大于 3"
            exit 1
        fi

        add_ip_to_blacklist_with_file $input_filepath
        ;;
    "")
        add_ip_to_blacklist_with_logs
        ;;
    *)
        echo -e "${Error}: 传参错误，只能传递 -i、-f 或者为空"
    esac

    reload_of_block_ip_type
    
}


# 删除黑名单数据的路由函数(解封 ip)
delete_ip_from_blacklist_router(){
    args_number=$#
    second_flag=$2
    input_filepath=$3

    # 清空返回值
    cat /dev/null > /tmp/add_ip_to_blacklist_return_code

    # 如果第二个参数为 -f 将执行批量删除黑名单的操作
    if [ "$second_flag" = "-f" ];then
        if [[ $args_number -gt 3 || $args_number -lt 3 ]];then
            echo -e "${Error}: 总参数个数不能小于 2 且不能大于 3"
            exit 1
        fi

        batch_delete_ip_from_blacklist $input_filepath

        reload_of_block_ip_type

        return 0 # 终断下面的程序继续执行
    fi

    # 当第二个参数不是 -f 时将接收到的数据传到 黑名单删除函数 中
    analysis_args $@

    if [ $args_number -lt 2 ];then
        echo -e "${Error}: 总参数个数不能小于 2"
        exit 1
    fi

    not_flags_len=`expr ${#args_arr[*]} - 1`

    
    for ip in "${args_arr[@]:1:$not_flags_len}"
    do 
        delete_ip_from_blacklist_with_input $ip
        return_code=$?
        echo $return_code >> /tmp/add_ip_to_blacklist_return_code
        if [ $return_code != 0 ];then  
            continue
        fi
    done

    reload_of_block_ip_type
}


# 路由函数
blacklist_router(){
    flag=$1

    # 下面的四个路径变量是为了避免代码很冗余才写到这里，不然每次内层函数调用都要获取文件路径
    # 获取 封禁/解禁 ip 的方式
    block_ip_type=$(get_section_value_from_config_path block_ip_type)
    code=$?
    print_return_code_message_of_get_section_path $code

    block_ip_type_result=$(get_block_ip_type_of_block_ip_handler $block_ip_type)

    unban_the_ip_type_result=$(get_block_ip_type_of_unban_ip_handler)

    # 获取日志文件存储路径
    log_path=$(get_section_value_from_config_path server_secure_log_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $log_path ];then
        err_code 104 "操作日志记录文件: $log_path 不存在..."
        exit 1
    fi

    # 获取黑名单路径
    blacklist_path=$(get_section_value_from_config_path blacklist_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $blacklist_path ];then
        err_code 104 "黑名单文件: $blacklist_path 不存在..."
        exit 1
    fi

    # 获取白名单路径
    whitelist_path=$(get_section_value_from_config_path whitelist_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $whitelist_path ];then
        err_code 104 "白名单文件: $whitelist_path 不存在..."
        exit 1
    fi

    # 参数判断
    case "$flag" in
    add)
        add_ip_to_blacklist_router $@
        ;;
    remove)
        delete_ip_from_blacklist_router $@
        ;;
    list)
        print_blacklist
        ;;
    merge|test|check)
        check_block_type_file_status
        ;;
    *)
        echo -e "${Error}: Usage: $0 {add -i|-f|为空}|{remove -i|-f|为空}|list"
        echo -e "${Info}: $0 add: 会自动查找 nginx secure 日志并封禁 ip"
        echo -e "${Info}: $0 add -i: 获取命令行中输入的 ip 并封禁，支持输入多个 ip"
        echo -e "${Info}: $0 add -f: 读取指定文件里的 ip 然后封禁"
        echo -e "${Info}: $0 remove: 解禁从命令行中输入的 ip, 支持输入多个 ip"
        echo -e "${Info}: $0 remove -f: 解禁从指定文件中读取到的 ip"
        echo -e "${Info}: $0 list: 打印黑名单列表"
        echo -e "${Info}: $0 test: 数据校对"
        exit 1
    ;;
    esac

    
}


blacklist_router $@


