#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

Btapi_Url='https://bt.cxinyun.com'
Check_Api=$(curl -Ss --connect-timeout 5 -m 2 $Btapi_Url/api/SetupCount)
if [ "$Check_Api" != 'ok' ];then
	Red_Error "宝塔云端无法连接，因此安装过程已中止！";
fi

if [ $(whoami) != "root" ];then
	echo "请使用root权限执行宝塔安装命令！"
	exit 1;
fi

is64bit=$(getconf LONG_BIT)
if [ "${is64bit}" != '64' ];then
	Red_Error "抱歉, 当前面板版本不支持32位系统, 请使用64位系统或安装宝塔5.9!";
fi

Centos6Check=$(cat /etc/redhat-release | grep ' 6.' | grep -iE 'centos|Red Hat')
if [ "${Centos6Check}" ];then
	echo "Centos6不支持安装宝塔面板，请更换Centos7/8安装宝塔面板"
	exit 1
fi 

UbuntuCheck=$(cat /etc/issue|grep Ubuntu|awk '{print $2}'|cut -f 1 -d '.')
if [ "${UbuntuCheck}" ] && [ "${UbuntuCheck}" -lt "16" ];then
	echo "Ubuntu ${UbuntuCheck}不支持安装宝塔面板，建议更换Ubuntu18/20安装宝塔面板"
	exit 1
fi

clear
#输出一条提示信息让用户确认是否安装
echo -e "\033[31m 欢迎使用宝塔Linux企业版一键安装脚本 \033[0m"
echo -e "\033[32m 创信博客: blog.cxinyun.cn \033[0m"
#echo -e "\033[31m 此脚本自2022年9月1日起暂停新用户安装 \033[0m"
#echo -e "\033[31m 未经授权安装可能会导致面板功能无法使用 \033[0m"
sleep 2s
echo -e "\033[31m 3秒后安装将继续 \033[0m"
sleep 1s
echo -e "\033[31m 2秒后安装将继续 \033[0m"
sleep 1s
echo -e "\033[31m 1秒后安装将继续 \033[0m"
sleep 1s

cd ~
setup_path="/www"
python_bin=$setup_path/server/panel/pyenv/bin/python
cpu_cpunt=$(cat /proc/cpuinfo|grep processor|wc -l)

if [ "$1" ];then
	IDC_CODE=$1
fi

GetSysInfo(){
	if [ -s "/etc/redhat-release" ];then
		SYS_VERSION=$(cat /etc/redhat-release)
	elif [ -s "/etc/issue" ]; then
		SYS_VERSION=$(cat /etc/issue)
	fi
	SYS_INFO=$(uname -a)
	SYS_BIT=$(getconf LONG_BIT)
	MEM_TOTAL=$(free -m|grep Mem|awk '{print $2}')
	CPU_INFO=$(getconf _NPROCESSORS_ONLN)

	echo -e ${SYS_VERSION}
	echo -e Bit:${SYS_BIT} Mem:${MEM_TOTAL}M Core:${CPU_INFO}
	echo -e ${SYS_INFO}

	if [ -z "${os_version}" ];then
		echo -e "============================================"
		echo -e "检测到为非常用系统安装,建议更换至Centos-7或Debian-10+或Ubuntu-20+系统安装宝塔面板"
		echo -e "详情请查看系统兼容表：https://docs.qq.com/sheet/DUm54VUtyTVNlc21H?tab=BB08J2"
		echo -e "特殊情况可通过以下联系方式寻求安装协助情况"
	fi

	is64bit=$(getconf LONG_BIT)
	if [ "${is64bit}" == '32' ];then
		echo -e "宝塔面板不支持32位系统进行安装，请使用64位系统/服务器架构进行安装宝塔"
		exit 1
	fi

	S390X_CHECK=$(uname -a|grep s390x)
	if [ "${S390X_CHECK}" ];then
		echo -e "宝塔面板不支持s390x架构进行安装，请使用64位系统/服务器架构进行安装宝塔"
		exit 1
	fi

	echo -e "============================================"
	echo -e "请截图以上报错信息发帖至论坛www.bt.cn/bbs求助"
}
Red_Error(){
	echo '=================================================';
	printf '\033[1;31;40m%b\033[0m\n' "$@";
	GetSysInfo
	exit 1;
}
Lock_Clear(){
	if [ -f "/etc/bt_crack.pl" ];then
		chattr -R -ia /www
		chattr -ia /etc/init.d/bt
		\cp -rpa /www/backup/panel/vhost/* /www/server/panel/vhost/
		mv /www/server/panel/BTPanel/__init__.bak /www/server/panel/BTPanel/__init__.py
		rm -f /etc/bt_crack.pl
	fi
}
Install_Check(){
	if [ "${INSTALL_FORCE}" ];then
		return
	fi
	echo -e "----------------------------------------------------"
	echo -e "检查已有其他Web/mysql环境，安装宝塔可能影响现有站点及数据"
	echo -e "Web/mysql service is alreday installed,Can't install panel"
	echo -e "----------------------------------------------------"
	echo -e "已知风险/Enter yes to force installation"
	read -p "输入yes强制安装: " yes;
	if [ "$yes" != "yes" ];then
		echo -e "------------"
		echo "取消安装"
		exit;
	fi
	INSTALL_FORCE="true"
}
System_Check(){
	MYSQLD_CHECK=$(ps -ef |grep mysqld|grep -v grep|grep -v /www/server/mysql)
	PHP_CHECK=$(ps -ef|grep php-fpm|grep master|grep -v /www/server/php)
	NGINX_CHECK=$(ps -ef|grep nginx|grep master|grep -v /www/server/nginx)
	HTTPD_CHECK=$(ps -ef |grep -E 'httpd|apache'|grep -v /www/server/apache|grep -v grep)
	if [ "${PHP_CHECK}" ] || [ "${MYSQLD_CHECK}" ] || [ "${NGINX_CHECK}" ] || [ "${HTTPD_CHECK}" ];then
		Install_Check
	fi
}
Set_Ssl(){
    echo -e ""
    echo -e "----------------------------------------------------------------------"
    echo -e "为了您的面板使用安全，建议您开启面板SSL，开启后请使用https访问宝塔面板"
    echo -e "输入y回车即开启面板SSL并进行下一步安装"
    echo -e "输入n回车跳过面板SSL配置，直接进行安装"
    echo -e "10秒后将跳过SSL配置，直接进行面板安装"
    echo -e "----------------------------------------------------------------------"
    echo -e ""
    read -t 10 -p "是否确定开启面板SSL ? (y/n): " yes

    if [ $? != 0 ];then
        SET_SSL=false
    else
        case "$yes" in
            y)
                SET_SSL=true
                ;;
            n)
                SET_SSL=false
				rm -f /www/server/panel/data/ssl.pl
                ;;
            *)
                Set_Ssl
        esac
    fi
}
Get_Pack_Manager(){
	if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
		PM="yum"
	elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
		PM="apt-get"		
	fi
}
Auto_Swap()
{
	swap=$(free |grep Swap|awk '{print $2}')
	if [ "${swap}" -gt 1 ];then
		echo "Swap total sizse: $swap";
		return;
	fi
	if [ ! -d /www ];then
		mkdir /www
	fi
	swapFile="/www/swap"
	dd if=/dev/zero of=$swapFile bs=1M count=1025
	mkswap -f $swapFile
	swapon $swapFile
	echo "$swapFile    swap    swap    defaults    0 0" >> /etc/fstab
	swap=`free |grep Swap|awk '{print $2}'`
	if [ $swap -gt 1 ];then
		echo "Swap total sizse: $swap";
		return;
	fi
	
	sed -i "/\/www\/swap/d" /etc/fstab
	rm -f $swapFile
}
Service_Add(){
	if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
		chkconfig --add bt
		chkconfig --level 2345 bt on
		Centos9Check=$(cat /etc/redhat-release |grep ' 9')
		if [ "${Centos9Check}" ];then
            wget -O /usr/lib/systemd/system/btpanel.service ${download_Url}/init/systemd/btpanel.service
			systemctl enable btpanel
		fi		
	elif [ "${PM}" == "apt-get" ]; then
		update-rc.d bt defaults
	fi 
}
Set_Centos_Repo(){
	HUAWEI_CHECK=$(cat /etc/motd |grep "Huawei Cloud")
	if [ "${HUAWEI_CHECK}" ] && [ "${is64bit}" == "64" ];then
		\cp -rpa /etc/yum.repos.d/ /etc/yumBak
		sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
		sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-*.repo
		rm -f /etc/yum.repos.d/epel.repo
		rm -f /etc/yum.repos.d/epel-*
	fi
	ALIYUN_CHECK=$(cat /etc/motd|grep "Alibaba Cloud ")
	if [  "${ALIYUN_CHECK}" ] && [ "${is64bit}" == "64" ] && [ ! -f "/etc/yum.repos.d/Centos-vault-8.5.2111.repo" ];then
		rename '.repo' '.repo.bak' /etc/yum.repos.d/*.repo
		wget https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo -O /etc/yum.repos.d/Centos-vault-8.5.2111.repo
		wget https://mirrors.aliyun.com/repo/epel-archive-8.repo -O /etc/yum.repos.d/epel-archive-8.repo
		sed -i 's/mirrors.cloud.aliyuncs.com/url_tmp/g'  /etc/yum.repos.d/Centos-vault-8.5.2111.repo &&  sed -i 's/mirrors.aliyun.com/mirrors.cloud.aliyuncs.com/g' /etc/yum.repos.d/Centos-vault-8.5.2111.repo && sed -i 's/url_tmp/mirrors.aliyun.com/g' /etc/yum.repos.d/Centos-vault-8.5.2111.repo
		sed -i 's/mirrors.aliyun.com/mirrors.cloud.aliyuncs.com/g' /etc/yum.repos.d/epel-archive-8.repo
	fi
	MIRROR_CHECK=$(cat /etc/yum.repos.d/CentOS-Linux-AppStream.repo |grep "[^#]mirror.centos.org")
	if [ "${MIRROR_CHECK}" ] && [ "${is64bit}" == "64" ];then
		\cp -rpa /etc/yum.repos.d/ /etc/yumBak
		sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
		sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-*.repo
	fi
}
get_node_url(){
	if [ ! -f /bin/curl ];then
		if [ "${PM}" = "yum" ]; then
			yum install curl -y
		elif [ "${PM}" = "apt-get" ]; then
			apt-get install curl -y
		fi
	fi

	if [ -f "/www/node.pl" ];then
		download_Url=$(cat /www/node.pl)
		echo "Download node: $download_Url";
		echo '---------------------------------------------';
		return
	fi
	
	echo '---------------------------------------------';
	echo "Selected download node...";
	nodes=(https://dg2.bt.cn https://dg1.bt.cn https://download.bt.cn);

	if [ "$1" ];then
		nodes=($(echo ${nodes[*]}|sed "s#${1}##"))
	fi

	tmp_file1=/dev/shm/net_test1.pl
	tmp_file2=/dev/shm/net_test2.pl
	[ -f "${tmp_file1}" ] && rm -f ${tmp_file1}
	[ -f "${tmp_file2}" ] && rm -f ${tmp_file2}
	touch $tmp_file1
	touch $tmp_file2
	for node in ${nodes[@]};
	do
		NODE_CHECK=$(curl --connect-timeout 3 -m 3 2>/dev/null -w "%{http_code} %{time_total}" ${node}/net_test|xargs)
		RES=$(echo ${NODE_CHECK}|awk '{print $1}')
		NODE_STATUS=$(echo ${NODE_CHECK}|awk '{print $2}')
		TIME_TOTAL=$(echo ${NODE_CHECK}|awk '{print $3 * 1000 - 500 }'|cut -d '.' -f 1)
		if [ "${NODE_STATUS}" == "200" ];then
			if [ $TIME_TOTAL -lt 100 ];then
				if [ $RES -ge 1500 ];then
					echo "$RES $node" >> $tmp_file1
				fi
			else
				if [ $RES -ge 1500 ];then
					echo "$TIME_TOTAL $node" >> $tmp_file2
				fi
			fi

			i=$(($i+1))
			if [ $TIME_TOTAL -lt 100 ];then
				if [ $RES -ge 3000 ];then
					break;
				fi
			fi	
		fi
	done

	NODE_URL=$(cat $tmp_file1|sort -r -g -t " " -k 1|head -n 1|awk '{print $2}')
	if [ -z "$NODE_URL" ];then
		NODE_URL=$(cat $tmp_file2|sort -g -t " " -k 1|head -n 1|awk '{print $2}')
		if [ -z "$NODE_URL" ];then
			NODE_URL='https://download.bt.cn';
		fi
	fi
	rm -f $tmp_file1
	rm -f $tmp_file2
	download_Url=$NODE_URL
	echo "Download node: $download_Url";
	echo '---------------------------------------------';
}
Remove_Package(){
	local PackageNmae=$1
	if [ "${PM}" == "yum" ];then
		isPackage=$(rpm -q ${PackageNmae}|grep "not installed")
		if [ -z "${isPackage}" ];then
			yum remove ${PackageNmae} -y
		fi 
	elif [ "${PM}" == "apt-get" ];then
		isPackage=$(dpkg -l|grep ${PackageNmae})
		if [ "${PackageNmae}" ];then
			apt-get remove ${PackageNmae} -y
		fi
	fi
}
Install_RPM_Pack(){
	yumPath=/etc/yum.conf
	Centos8Check=$(cat /etc/redhat-release | grep ' 8.' | grep -iE 'centos|Red Hat')
	if [ "${Centos8Check}" ];then
		Set_Centos_Repo
	fi	
	isExc=$(cat $yumPath|grep httpd)
	if [ "$isExc" = "" ];then
		echo "exclude=httpd nginx php mysql mairadb python-psutil python2-psutil" >> $yumPath
	fi

	#SYS_TYPE=$(uname -a|grep x86_64)
	#yumBaseUrl=$(cat /etc/yum.repos.d/CentOS-Base.repo|grep baseurl=http|cut -d '=' -f 2|cut -d '$' -f 1|head -n 1)
	#[ "${yumBaseUrl}" ] && checkYumRepo=$(curl --connect-timeout 5 --head -s -o /dev/null -w %{http_code} ${yumBaseUrl})	
	#if [ "${checkYumRepo}" != "200" ] && [ "${SYS_TYPE}" ];then
	#	curl -Ss --connect-timeout 3 -m 60 http://download.bt.cn/install/yumRepo_select.sh|bash
	#fi
	
	#尝试同步时间(从bt.cn)
	echo 'Synchronizing system time...'
	getBtTime=$(curl -sS --connect-timeout 3 -m 60 http://www.bt.cn/api/index/get_time)
	if [ "${getBtTime}" ];then	
		date -s "$(date -d @$getBtTime +"%Y-%m-%d %H:%M:%S")"
	fi

	if [ -z "${Centos8Check}" ]; then
		yum install ntp -y
		rm -rf /etc/localtime
		ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

		#尝试同步国际时间(从ntp服务器)
		ntpdate 0.asia.pool.ntp.org
		setenforce 0
	fi

	startTime=`date +%s`

	sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
	#yum remove -y python-requests python3-requests python-greenlet python3-greenlet
	yumPacks="libcurl-devel wget tar gcc make zip unzip openssl openssl-devel gcc libxml2 libxml2-devel libxslt* zlib zlib-devel libjpeg-devel libpng-devel libwebp libwebp-devel freetype freetype-devel lsof pcre pcre-devel vixie-cron crontabs icu libicu-devel c-ares libffi-devel bzip2-devel ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel qrencode"
	yum install -y ${yumPacks}

	for yumPack in ${yumPacks}
	do
		rpmPack=$(rpm -q ${yumPack})
		packCheck=$(echo ${rpmPack}|grep not)
		if [ "${packCheck}" ]; then
			yum install ${yumPack} -y
		fi
	done
	if [ -f "/usr/bin/dnf" ]; then
		dnf install -y redhat-rpm-config
	fi

	ALI_OS=$(cat /etc/redhat-release |grep "Alibaba Cloud Linux release 3")
	if [ -z "${ALI_OS}" ];then 
		yum install epel-release -y
	fi
}
Install_Deb_Pack(){
	ln -sf bash /bin/sh
	UBUNTU_22=$(cat /etc/issue|grep "Ubuntu 22")
	if [ "${UBUNTU_22}" ];then
		apt-get remove needrestart -y
	fi
	ALIYUN_CHECK=$(cat /etc/motd|grep "Alibaba Cloud ")
	if [ "${ALIYUN_CHECK}" ] && [ "${UBUNTU_22}" ];then
		apt-get remove libicu70 -y
	fi
	apt-get update -y
	apt-get install bash -y
	if [ -f "/usr/bin/bash" ];then
		ln -sf /usr/bin/bash /bin/sh
	fi
	apt-get install ruby -y
	apt-get install lsb-release -y
	#apt-get install ntp ntpdate -y
	#/etc/init.d/ntp stop
	#update-rc.d ntp remove
	#cat >>~/.profile<<EOF
	#TZ='Asia/Shanghai'; export TZ
	#EOF
	#rm -rf /etc/localtime
	#cp /usr/share/zoneinfo/
