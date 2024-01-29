#!/bin/bash
# desc: 生成配置文件
# date: 2023-12-04 15:00
# author: echoxu
# 功能: 生成可自定义的配置文件

. lib/common
. lib/blacklist
. lib/nginx
. lib/firewall


# 设置默认值：当输入为空时
get_config_file_section_default_value(){
    section_name=$1
    section_value=''

    case "$section_name" in
    FilePath)
        section_value=${HOME}/.server_secure.conf
        ;;
    nginxlog_path)
        section_value=/usr/share/nginx/logs/Access.log
        ;;
    securelog_path)
        section_value=/var/log/secure
        ;;
    limit_count)
        section_value=0
        ;;
    blacklist_path)
        section_value=${HOME}/.blacklist
        ;;
    whitelist_path)
        section_value=${HOME}/.whitelist
        ;;
    server_secure_log_path)
        section_value=${HOME}/server_secure.log
        ;;
    block_ip_type)
        section_value=firewalld
        ;;
    *)
        ;;
    esac

    echo $section_value
}


# 检查封禁 ip 的方式, 1 为防火墙 2 为 Nginx host deny file
valid_block_ip_type_from_input(){
    block_ip_type=$1
    
    case "$block_ip_type" in
    1)
        block_ip_type=firewalld
        ;;
    2)
        block_ip_type=nginx
        ;;
    *)
        return 106
    ;;
    esac

    echo $block_ip_type
}


# 数据校验：当输入不为空时
valid_data_from_input(){
    valid_data_name=$1
    valid_section_value=$2

    case "$valid_data_name" in
    FilePath|nginxlog_path|securelog_path|blacklist_path|whitelist_path|server_secure_log_path)
        real_path=$(get_real_path $section_value)
        is_path_result=$(vaild_is_path_from_input $real_path)
        code=$?
        if [ $code != 0 ];then
            return $code            # 校验不通过继续往上层调用返回错误码
        else
            echo $is_path_result
        fi
        ;;
    limit_count)
        is_number_result=$(vaild_is_number_from_input $valid_section_value)
        code=$?
        if [ $code != 0 ];then
            return $code
        else
            echo $is_number_result
        fi
        ;;
    block_ip_type)
        is_correct_input=$(valid_block_ip_type_from_input $valid_section_value)
        code=$?
        if [ $code != 0 ];then
            return $code
        else
            echo $is_correct_input
        fi
        ;;
    *)
        ;;
    esac

}


# 中间函数
config_file_add_section_handler(){
    section_name=$1
    section_value=$2

    if [ -z "$section_value" ];then
        section_value=$(get_config_file_section_default_value $section_name)
    else
        valid_result=$(valid_data_from_input $section_name $section_value)
        code=$?
        if [ $code != 0 ];then
            return $code
        else
            section_value=$valid_result
        fi
    fi

    echo $section_value
}


# 配置文件添加数据
config_file_add_section(){
    section_name=$1
    section_value=$2

    section_handler_result=$(config_file_add_section_handler $section_name $section_value)
    code=$?
    if [ $code != 0 ];then
        case "$code" in
        100)
            err_code $code "$values_from_args 是一个目录路径，请输入正确的文件路径..."
            exit 1
            ;;
        104)
            err_code $code "$values_from_args 文件不存在，请先创建它..."
            exit 1
            ;;
        101)
            err_code $code "抱歉，你无法对 $values_from_args 进行读写操作..."
            exit 1
            ;;
        102)
            err_code $code "你输入的: $values_from_args 不是一个数字..."
            exit 1
            ;;
        106)
            err_code $code "你输入的: $values_from_args 不在当前设定的区间范围内,请输入 1 或者 2..."
            exit 1
            ;;
        esac
    else
        section_value=$section_handler_result
    fi

    # 保存配置文件路径
    if [[ $section_name == "FilePath" ]];then
        echo "FilePath=$section_value" > $config_path_temp
    fi
    
    get_config_path_result=$(get_config_path)
    echo "$section_name=$section_value" >> $get_config_path_result
}


# 设置配置文件参数
set_config_path(){
    while true
    do
        echo "该命令将创建一个配置文件，在其中存储配置信息。"

        read -p "请输入配置文件路径 (回车将使用 ~/.blascklist.conf 作为默认配置文件路径):" config_path
        config_file_add_section FilePath $config_path
        
        get_config_path_result=$(get_config_path)
        cat /dev/null > $get_config_path_result

        read -p "请输入 nginx 日志路径 (回车将使用 /usr/share/nginx/logs/Access.log 作为路径): " nginxlog_path
        config_file_add_section nginxlog_path $nginxlog_path

        read -p "请输入 secure 日志路径 (回车将使用 /var/log/secure 作为路径): " securelog_path
        config_file_add_section securelog_path $securelog_path

        read -p "请输入 limit (回车将使用 0 作为其值): " limit_count
        config_file_add_section limit_count $limit_count

        read -p "请输入 黑名单 文件路径 (回车将使用 ~/.blacklist 作为路径): " blacklist_path
        config_file_add_section blacklist_path $blacklist_path

        read -p "请输入 白名单 文件路径 (回车将使用 ~/.whitelist 作为路径): " whitelist_path
        config_file_add_section whitelist_path $whitelist_path

        read -p "请输入 黑名单/白名单 操作日志路径 (回车将使用 ~/server_secure.log 作为路径): " server_secure_log_path
        config_file_add_section server_secure_log_path $server_secure_log_path
        
        echo && echo -e "${Tip}: 请仔细阅读并选择使用何种方案来封禁 ip"
        echo -e "${Tip}: 使用防火墙方案不用重启 Nginx，但误封操作可能导致 SSH 连接失败"
        echo -e "${Tip}: 使用 Ningx Host Deny 方案需要重启 Nginx，但不会影响 SSH 连接"
    
        echo && echo -e "${Red_font_prefix}${Font_color_suffix}${Green_font_prefix}1.使用 Firewwall${Font_color_suffix}"
        echo -e "${Green_font_prefix}2.使用 Nginx Host Deny${Font_color_suffix}" && echo

        read -p "请输入 [1-2] 来选择封禁 ip 的方案 (回车将使用 防火墙 来封禁 ip): " block_ip_type
        config_file_add_section block_ip_type $block_ip_type

        break
    done

    echo && echo -e "你使用了 ${Green_font_prefix}[$get_config_path_result]${Font_color_suffix} 作为配置文件路径" && echo
    
}


# 打印配置文件路径
print_config_file_path(){
    config_path=$(get_config_path)
    
    # 用于接收被调用方的返回值并将此返回值继续返回给调用方
    # 当函数调用层数过多(超过两层)时再继续用 echo 作为函数返回值的话会导致最里层的调用函数的错误信息无法正确打印
    code=$?
    if [ $code != 0 ];then
        return $code
    fi

    echo $config_path
}


# handler 函数
block_ip_type_change_handler(){
    block_ip_type_input=$1

    block_ip_type_after_change=''

    if [ "$block_ip_type_input" = "firewalld" ];then
        block_ip_type_after_change=nginx
    fi

    if [ "$block_ip_type_input" = "nginx" ];then
        block_ip_type_after_change=firewalld
    fi

    echo $block_ip_type_after_change
}


# 数据迁移: 将防火墙数据或 nginx host deny 数据迁移并导入
migrate_data(){
    block_ip_type_input=$1

    log_path=$(get_section_value_from_config_path server_secure_log_path)
    code=$?
    print_return_code_message_of_get_section_path $code
    if [ ! -f $log_path ];then
        err_code 104 "操作日志记录文件: $log_path 不存在..."
        exit 1
    fi

    # firewalld->nginx
    if [ "$block_ip_type_input" = "firewalld" ];then

        nginx_deny_file_path=$(get_nginx_host_deny_path)

        # 有备份需求可开启
        # datatime=`date +'%F-%T'`
        # sudo cp $nginx_deny_file_path $nginx_deny_file_path-${datatime}

        firewall_ip=$(firewall_op_with_get)

        cat $nginx_deny_file_path |awk -F ' '  '{print $2}'|awk -F ';' '{print $1}' > /tmp/format_nginx_deny_file.txt
        cat $firewall_ip /tmp/format_nginx_deny_file.txt |sort|uniq -d > /tmp/firewall_nginx_common.txt   # 两个文件共同拥有的内容
        cat $firewall_ip /tmp/firewall_nginx_common.txt |sort|uniq -u > /tmp/firewall_exclude_common.txt     # 除去共同部分，只在 firewalld 中独有的，也就是我们需要添加进 nginx deny file 中的
        
        if [ `cat /tmp/firewall_exclude_common.txt|wc -l` = 0 ];then
            return 208
        fi

        # 读取文件优先使用 read line 不要使用 cat, cat 速度比较慢
        while read line || [ -n "$line" ]
        do
            sudo echo "deny $line;" >> $nginx_deny_file_path
            echo -e "${Succeed}: IP: $line 已添加进 Nginx host deny 中."
            echo "$(date +'%F-%T') 已封禁入侵ip(f2n+): $line" >> $log_path
            
        done < "/tmp/firewall_exclude_common.txt"

        md5sum $nginx_deny_file_path |awk '{print $1}' > /tmp/.nginx_deny_md5

        reload_nginx
    fi

    # nginx->firewalld
    if [ "$block_ip_type_input" = "nginx" ];then
        nginx_host_deny_ip_file=$(get_nginx_host_deny_path)
        blacklist_path=$(get_section_value_from_config_path blacklist_path)
        code=$?
        print_return_code_message_of_get_section_path $code
        if [ ! -f $blacklist_path ];then
            err_code 104 "黑名单文件: $blacklist_path 不存在..."
            exit 1
        fi

        # 有备份需求可开启
        # datatime=`date +'%F-%T'`
        # cp $blacklist_path $blacklist_path-${datatime}

        firewall_ip=$(firewall_op_with_get)

        #  使 firewalld 和 blacklist 数据一致(在该脚本未上线之前，firewalld 数据是要多余 blacklist )
        cat $blacklist_path $firewall_ip |sort|uniq -d > /tmp/blacklist_firewall_common.txt
        cat $firewall_ip /tmp/blacklist_firewall_common.txt |sort|uniq -u > /tmp/firewall_exclude_blcak_common.txt  # 获取 firewalld 新增的内容
        while read line || [ -n "$line" ]
        do
            if [ -z $line ];then
                echo "黑名单和防火墙数据一致，无需同步..."
            else
                echo $line >> $blacklist_path
                echo -e "${Info}: IP: $line 已添加进黑名单列表中."
            fi
        done < "/tmp/firewall_exclude_blcak_common.txt"
        

        cat $nginx_host_deny_ip_file |awk -F ' '  '{print $2}'|awk -F ';' '{print $1}' > /tmp/format_nginx_deny_file.txt
        cat $firewall_ip /tmp/format_nginx_deny_file.txt |sort|uniq -d > /tmp/firewall_nginx_common.txt
        cat /tmp/format_nginx_deny_file.txt /tmp/firewall_nginx_common.txt |sort|uniq -u > /tmp/nginx_exclude_firewall_common.txt  # 获取 nginx deny file 新增的内容

        if [ `cat /tmp/nginx_exclude_firewall_common.txt|wc -l` = 0 ];then
            return 208
        fi

        while read line || [ -n "$line" ]
        do
            # 这里不使用 firewall_op_with_add $line 是因为这个函数要校验是否在防火墙中存在，这个非常耗时
            sudo /usr/bin/firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$line drop" > /dev/null 2>&1
            echo -e "${Succeed}: IP: $line 已添加进防火墙列表中."
            echo $line >> $blacklist_path
            echo -e "${Succeed}: IP: $line 已添加进黑名单列表中."
            echo "$(date +'%F-%T') 已封禁入侵ip(n2f+): $line" >> $log_path
            
        done < "/tmp/nginx_exclude_firewall_common.txt"

        md5sum $blacklist_path |awk '{print $1}' > /tmp/.blacklist_md5

        firewalld_reload
    fi
}


# 更换现有的封禁 ip 的方案, 如 firewalld 换为 nginx
# todo: 是否删除原来 firewall 中的数据
block_ip_type_change(){
    block_ip_type_res=$(get_section_value_from_config_path block_ip_type)
    code=$?
    print_return_code_message_of_get_section_path $code
    
    echo -e "${Info}: 当前封禁 ip 的方案为: $block_ip_type_res"
    res_after_change=$(block_ip_type_change_handler $block_ip_type_res)
    echo -e "${Tip}: 你确定要更改为使用 $res_after_change 方案吗 (y/n)?"

    read -p "请输入 (y/n)" answer

    case $answer in
    y|Y|yes)
        conf_path_res=$(get_config_path)
        echo -e "${Succeed}: 操作已确认，修改后的封禁 ip 方案为 : $res_after_change"

        echo -e "${Tip}: 正在进行数据迁移操作，请耐心等待..." && echo
        # echo "开始时间：$(date +'%F-%T')" 
        migrate_data $block_ip_type_res
        code=$?
        if [ $code = 208 ];then
            echo -e "${Tip}: $block_ip_type_res 未新增数据，$res_after_change 列表无需更新..."
        fi
        # echo "结束时间：$(date +'%F-%T')"

        rm -rf /tmp/blacklist_firewall_common.txt /tmp/firewall_exclude_blcak_common.txt /tmp/firewall_exclude_common.txt
        rm -rf /tmp/format_nginx_deny_file.txt /tmp/firewall_nginx_common.txt /tmp/nginx_exclude_firewall_common.txt
        rm -rf /tmp/firewall_rules_ip*
       
        sed -i 's/block_ip_type='"${block_ip_type_res}"'/block_ip_type='"${res_after_change}"'/' $conf_path_res
        echo -e "${Succeed}: 已将原方案：$block_ip_type_res 中的数据迁移到 $res_after_change 里"
        ;;
    n|N|no)
        echo -e "${Info}: 取消操作，当前封禁 ip 的方案为: $block_ip_type_res"
        ;;
    *)
        echo -e "${Error}: 请输入 y/n"
        ;;
    esac

}


# 配置文件路由函数
config_router(){
    flags=$1
    case "$flags" in
    config|-c)
        set_config_path
        ;;
    find|-f)
        result=$(print_config_file_path)
        code=$?
        if [ $code != 0 ];then
            err_code $code "没有找到配置文件, 请先用 $0 -c 来创建它..."
        else
            echo -e "${Info}: 配置文件路径为：$result"
        fi 
        ;;
    migrate|-m)
        block_ip_type_change
        ;;
    *)
        echo -e "${Error}: Usage: $0 -c|-f|-m"
        echo -e "${Info}: -c: 生成配置文件"
        echo -e "${Info}: -f: 查找配置文件路径"
        echo -e "${Info}: -m: 变更封禁 ip 的方案"
        return 1
    ;;
    esac
}


config_router $1
