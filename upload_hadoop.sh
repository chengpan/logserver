#!/bin/bash

function send_warning()
{
	title=$1
	content=$2
	curl -H 'Accept:application/json' --data-urlencode "id=10075" --data-urlencode "title=${title}" --data-urlencode "content=${content}" http://106.75.0.234/monitor.cgi
}

if [ $# -ne 3 ]
then
	echo "give me a download path and a tempory path and a working log path"
	exit
fi

download_dir=$1"/"
temp_log_dir=$2"/"
working_log_dir=$3"/"
err_log=${working_log_dir}"err_log"
tmp_file_list=${working_log_dir}"tmp_file_list"
process_pid=${working_log_dir}"process_pid"
process_busy=${working_log_dir}"process_busy"
send_request_url="http://10.9.139.51/send_request.lua"
record_file_url="http://10.9.139.51/record_hadoop_file.lua"
hadoop_logs_dir="/logs/"

echo "download_dir: ${download_dir}, where you store your logs"
echo "temp_log_dir: ${temp_log_dir}, where I move the logs there and send them to hadoop"
echo "working_log_dir: ${working_log_dir}, where I log everything in order to debug and info"
echo "err_log: ${err_log}, where I record anything worth noticing"
echo "tmp_file_list: ${tmp_file_list}, list files that need sending to hadoop"
echo "send_request_url: ${send_request_url}, request before sending to hadoop, like a mutex"
echo "record_file_url: ${record_file_url}, record uploaded file in hadoop to mysql"
echo "hadoop_logs_dir: ${hadoop_logs_dir}, where hadoop store its logs"
echo "process_pid: ${process_pid}, the pid of current working process, $$"
echo "process_busy: ${process_busy}, record message where two working process collide"

[ -d ${working_log_dir} ] || mkdir -p ${working_log_dir}

#保证只有一个进程在上传
if [ -f ${process_pid} ]
then
	echo "${process_pid} exists" | tee -a ${process_busy}
	date | tee -a ${process_busy}
	pid=`cat ${process_pid}`
	found=`ps ax | awk '{ print $1 }' | grep -e "^${pid}$"`
	if [ -n "${found}" ]
	then
		echo "upload process exists! pid = ${pid}, this is serious !!!" | tee -a ${process_busy}
		exit
	else
		echo "upload process doesnot exist! crashed ???" | tee -a ${process_busy}
	fi
fi

echo $$ > ${process_pid}

echo "work starts here, at `date`" | tee -a ${err_log}
start_timestamp=`date +%s`

#查找日志文件10min没有更新了
find ${download_dir} -type f  -mmin +10 -fprint ${tmp_file_list}
wc -l ${tmp_file_list} | tee -a ${err_log}

#file_path: /data/log_server/download/20161121/www.liebao.cn/small_2016112115_access.log
#先把要上传的文件mv至临时目录
while read file_path
do
	file_name=`basename ${file_path}` #small_2016112115_access.log
	file_dir=`dirname ${file_path}` #/data/log_server/download/20161121/www.liebao.cn
	file_dir_name=`basename ${file_dir}` #www.liebao.cn
	domain_name=${file_dir_name} #www.liebao.cn

	file_dir_dir=`dirname ${file_dir}` #/data/log_server/download/20161121
	file_dir_dir_name=`basename ${file_dir_dir}` #20161121
	file_date=${file_dir_dir_name} #20161121

	echo "${file_date}, ${domain_name}, ${file_name}"

	mv_target_dir=${temp_log_dir}${file_date}/${domain_name}/
	mv_target_path=${mv_target_dir}${file_name}

	[ -d ${mv_target_dir} ] || mkdir -p ${mv_target_dir}

	if [ -f ${mv_target_path} ]
	then
		echo "${mv_target_path} exists!, last time failed ?" | tee -a ${err_log}
	else
		mv ${file_path} ${mv_target_path}
	fi
done < ${tmp_file_list}	

echo "mv completed !, now wait for 5s so the moved files won't be appending data"
sleep 5
date | tee -a ${err_log}

find ${temp_log_dir} -type f -fprint ${tmp_file_list}
wc -l ${tmp_file_list} | tee -a ${err_log}

#一一检查上传
declare -i send_success=0
declare -i send_failure=0

file_entries=`wc -l ${tmp_file_list} | awk '{print $1}'`
declare -i file_num=0

while read file_path
do
	file_name=`basename ${file_path}` #small_2016112115_access.log
	file_dir=`dirname ${file_path}` #/data/log_server/download/20161121/www.liebao.cn
	file_dir_name=`basename ${file_dir}` #www.liebao.cn
	domain_name=${file_dir_name} #www.liebao.cn

	file_dir_dir=`dirname ${file_dir}` #/data/log_server/download/20161121
	file_dir_dir_name=`basename ${file_dir_dir}` #20161121
	file_date=${file_dir_dir_name} #20161121

	let file_num++
	echo "${file_num} of ${file_entries} at `date`"
	echo "${file_date}, ${domain_name}, ${file_name}"

	yes_to_send=`curl --silent "${send_request_url}?request=lock&file_date=${file_date}&domain_name=${domain_name}&file_name=${file_name}"`
	if [ "${yes_to_send}" != "yes_to_send" ]
	then
		echo "try to send ${file_path} not permitted, msg: ${yes_to_send}" | tee -a ${err_log}
		let send_failure++
		continue
	fi

	hadoop_dest_path=${hadoop_logs_dir}${file_date}/${domain_name}/${file_name}

	echo "appending ${file_path} to ${hadoop_dest_path}"

	hdfs dfs -appendToFile ${file_path} ${hadoop_dest_path} >> ${err_log} 2>&1

	if [ $? -ne 0 ]
	then
		echo "hdfs dfs -appendToFile ${file_path} ${hadoop_dest_path} error !" | tee -a ${err_log}
		let send_failure++
	else
		let send_success++
		rm -f ${file_path}
	fi

	curl --silent "${send_request_url}?request=unlock&file_date=${file_date}&domain_name=${domain_name}&file_name=${file_name}"
	
	record_success=`curl --silent "${record_file_url}?file_date=${file_date}&domain_name=${domain_name}&file_name=${file_name}"`
	if [ "${record_success}" != "record_success" ]
	then
		echo "record file to mysql failed, msg: ${record_success}" | tee -a ${err_log}
		echo "curl --silent \"${record_file_url}?file_date=${file_date}&domain_name=${domain_name}&file_name=${file_name}\"" | tee -a ${err_log}
		let send_failure++
	fi
done < ${tmp_file_list}	

finish_timestamp=`date +%s`
run_time=`expr ${finish_timestamp} - ${start_timestamp}`

echo "run_time: ${run_time}, success : ${send_success}, failures: ${send_failure}" | tee -a ${err_log}

if [ ${send_failure} -gt 0 -o ${run_time} -gt 1800 ]
then
	send_warning "hadoop上传" "run_time: ${run_time}, success : ${send_success}, failures: ${send_failure}"
fi

#删除2天前日志目录
time_str=`date -d "-2 day" "+%Y%m%d"`
[ -d ${download_dir}${time_str} ] && rm -rf ${download_dir}${time_str}
[ -d ${temp_log_dir}${time_str} ] && rm -rf ${temp_log_dir}${time_str}

#错误日志不要太长
file_entries=`wc -l ${err_log} | awk '{print $1}'`
if [ $file_entries -gt 150000 ]
then
	sed -e '1,50000d' -i ${err_log}
fi

#进程结束
rm -f ${process_pid}
