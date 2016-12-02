#!/bin/bash

#设置环境
source /etc/profile

function send_warning()
{
	title=$1
	content=$2
	curl -H 'Accept:application/json' --data-urlencode "id=10075" --data-urlencode "title=${title}" --data-urlencode "content=${content}" http://106.75.0.234/monitor.cgi
}

logs_dir="/data/log_server/logs/"
get_domains_url="http://10.9.139.51/get_download_whole_domains.lua"
routine_work_log_dir="/data/log_server/routine_work_log/"
err_log=${routine_work_log_dir}"err_log"
process_pid=${routine_work_log_dir}"process_pid"
process_busy=${routine_work_log_dir}"process_busy"

[ -d ${routine_work_log_dir} ] || mkdir -p ${routine_work_log_dir}

#保证只有一个进程在上传
if [ -f ${process_pid} ]
then
	echo "${process_pid} exists" | tee -a ${process_busy}
	date | tee -a ${process_busy}
	pid=`cat ${process_pid}`
	found=`ps ax | awk '{ print $1 }' | grep -e "^${pid}$"`
	if [ -n "${found}" ]
	then
		echo "process exists! pid = ${pid}, this is serious !!!" | tee -a ${process_busy}
		exit
	else
		echo "process doesnot exist! crashed ???" | tee -a ${process_busy}
	fi
fi

echo $$ > ${process_pid}

echo "work starts here, at `date`" | tee -a ${err_log}
start_timestamp=`date +%s`

domain_names=`curl --silent --max-time 3 ${get_domains_url} | xargs`
echo "downloading for $domain_names"
for domain in ${domain_names}; do
	echo "downloading for ${domain} at `date`" | tee -a ${err_log}
	for hour in -1 -2 -3 -4 -5; do
		for file_type in "small" "big"; do
			file_date=`date -d "${hour} hour" "+%Y%m%d"`
			file_date_hour=`date -d "${hour} hour" "+%Y%m%d%H"`
			hdfs_file_location="/logs/"${file_date}"/"${domain}"/"${file_type}"_"${file_date_hour}"_access.log"
			local_file_location=${logs_dir}${file_date}"/"${domain}"/"${file_type}"_"${file_date_hour}"_access.log"
			
			echo "downloading ${hdfs_file_location} to ${local_file_location}"

			if [ -f ${local_file_location} ]; then
				echo "${local_file_location} has been there"
				continue
			fi

			hdfs dfs -test -f ${hdfs_file_location}

			if [ $? -ne 0 ]; then
				echo "${hdfs_file_location} doesnot exist"
				continue 
			fi

			mkdir -p `dirname ${local_file_location}`

			curl --silent "http://10.9.101.54:50070/webhdfs/v1"${hdfs_file_location}"?op=OPEN" -L | gzip --fast > ${local_file_location}
			if [ $? -ne 0 ]; then
				echo "download ${hdfs_file_location} failed" | tee -a ${err_log}
				rm -f ${local_file_location}
			fi

		done
	done
done

#删除30天以前的日志
old_log_date=`date -d "-30 days" "+%Y%m%d"`
old_log_dir=${logs_dir}${old_log_date}

echo "removing ${old_log_dir}"
rm -rf ${old_log_dir}

#删除10天未访问的日志
find ${logs_dir} -type f -atime +10 -delete


