#!/bin/bash

function send_warning()
{
	title=$1
	content=$2
	last_warning_file="/tmp/last_warning"
	[ -f ${last_warning_file} ] || echo 1 > ${last_warning_file}
	last_warning_time=`cat ${last_warning_file}`
	current_timestamp=`date +%s`
	time_gap=$(( current_timestamp - last_warning_time ))
	echo ${last_warning_time}, ${current_timestamp}, ${time_gap}

	if [ ${time_gap} -gt 3600 ]
	then
		echo "send warning: ${title}, ${content}"
		echo ${current_timestamp} > ${last_warning_file}
		curl -H 'Accept:application/json' --data-urlencode "id=10075" --data-urlencode "title=${title}" --data-urlencode "content=${content}" http://106.75.87.81/monitor.cgi
	fi
}

iplist=`/sbin/ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' | xargs`
sfdir="/usr/local/ats/var/log/trafficserver/"
bfdir="/usr/local/icdncache_svr/log/"

#小文件
logdir=${sfdir}
file_prefix="small_"
file_suffix="_access.log"

if [ -d ${bfdir} ]
then
	#大文件
	file_prefix="big_"
	logdir=${bfdir}
fi

echo "logdir: ${logdir}"
rand_seed=$RANDOM
((rand_num=rand_seed%300))
echo "sleep ${rand_num}"
sleep ${rand_num}

upload_info_dir="/root/upload_log/upload/"
upload_info_file=${upload_info_dir}"upload_info"
tmp_upload_file_list=${upload_info_dir}"tmp_upload_file_list"
upload_failed_file_list=${upload_info_dir}"upload_failed_file_list"
upload_err_log=${upload_info_dir}"err_log"
upload_process_pid=${upload_info_dir}"upload_process_pid"
upload_process_busy=${upload_info_dir}"upload_process_busy"
upload_server="http://106.75.87.81/savelog.lua"

#存放所有已经上传的文件信息以及出错信息
[ -d ${upload_info_dir} ] || mkdir ${upload_info_dir}

#避免grep, sed报错
[ -f ${upload_info_file} ] || touch ${upload_info_file}
[ -f ${upload_failed_file_list} ] || touch ${upload_failed_file_list}

#保证只有一个进程在上传
if [ -f ${upload_process_pid} ]
then
	echo "${upload_process_pid} exists" >> ${upload_process_busy}
	date >> ${upload_process_busy}

	pid=`cat ${upload_process_pid}`
	ps ax | awk '{ print $1 }' | grep -e "^${pid}$"
	if [ $? -eq 0 ]
	then
		echo "upload process exists! pid = ${pid}, this is serious !!!" >> ${upload_process_busy}
		exit 1
	else
		echo "upload process doesnot exist! crashed ???" >> ${upload_process_busy}
	fi
fi

echo $$ > ${upload_process_pid}

rm -f ${tmp_upload_file_list}


if [ -d ${bfdir} ]
then
	#大文件
	find ${logdir} -mindepth 2 -maxdepth 2 -name "http_access*.log.1" -type f -size +10c -mmin -300 -fprint ${tmp_upload_file_list}
else
	#小文件
	find ${logdir} -mindepth 2 -maxdepth 2 ! -path "*/accesslog/*" -name "ats_*.log" -type f -size +10c -mmin -300 -fprint ${tmp_upload_file_list}
fi

#上传失败的要重传
[ -f ${upload_failed_file_list} ] && cat ${upload_failed_file_list} | grep -v "aabbccdd" >> ${tmp_upload_file_list}

declare -i upload_success=0
declare -i upload_failures=0
declare -i skiped_files=0

echo >> ${upload_err_log}
echo "upload started at : " >> ${upload_err_log}
date >> ${upload_err_log}
start_timestamp=`date +%s`
echo "total log files: " >> ${upload_err_log}
wc ${tmp_upload_file_list} -l >> ${upload_err_log} 
while read file 
do
	grep "${file}" ${upload_info_file} > /dev/null
	
	if [ $? -eq 0 ]
	then
		echo ${file} has been uploaded !
		let skiped_files++
		continue
	fi

	if [ ! -f ${file} ]
	then
		echo "${file} does not exist any more" >> ${upload_err_log}
		sed -e "s#${file}#aabbccdd#g" -i ${upload_failed_file_list}
		continue
	fi

	echo "ready to upload ${file}"

	file_name=`basename ${file}`
	domain_name=`dirname ${file}`
	domain_name=`basename ${domain_name}`
	echo "${domain_name}, ${file_name}"

	time_min=`echo ${file_name} | grep -E -o "[0-9]{12}"`
	time_hour=`echo ${time_min} | grep -E -o "^[0-9]{10}"`
	file_date=`echo ${time_min} | grep -E -o "^[0-9]{8}"`
	file_name=${file_prefix}${time_hour}${file_suffix}
	echo "${file_name}, ${file_date}"

	file_msize=`du -m ${file} | awk '{print $1}'`
	min_time=10
	((max_time = file_msize + min_time))
	echo "curl max time: ${max_time}"

	curl_start_timestamp=`date +%s`
	curl --silent --connect-timeout 3 --max-time ${max_time} --data-binary @${file} "${upload_server}?domain_name=${domain_name}&file_name=${file_name}&file_date=${file_date}" | grep "upload_success"
	if [ $? -ne 0 ]
	then
		#记录出错信息
		date >> ${upload_err_log}
		echo "upload failed" >> ${upload_err_log}
		echo "curl --silent --connect-timeout 3 --max-time ${max_time} --data-binary @${file} \"${upload_server}?domain_name=${domain_name}&file_name=${file_name}&file_date=${file_date}\"" >> ${upload_err_log}
		curl_finish_timestamp=`date +%s`
		curl_run_time=`expr ${curl_finish_timestamp} - ${curl_start_timestamp}`
		echo "curl_run_time: ${curl_run_time}" >> ${upload_err_log}
		let upload_failures++

		echo ${file} >> ${upload_failed_file_list}
		#同一文件多次上传失败报警
		num=`grep "${file}" ${upload_failed_file_list} | wc -l`
		if [ ${num} -gt 5 ]
		then
			send_warning "多次上传" "${file} failed ${num} times, iplist: ${iplist}"
		fi

	else
		#记录成功信息
		echo ${file} >> ${upload_info_file}
		#删除失败信息
		sed -e "s#${file}#aabbccdd#g" -i ${upload_failed_file_list}
		let upload_success++
	fi

done < ${tmp_upload_file_list}

#删除已经成功的失败文件记录
sed -e '/aabbccdd/d' -i ${upload_failed_file_list}

echo "upload finished at : " >> ${upload_err_log}
date >> ${upload_err_log}
finish_timestamp=`date +%s`
echo "#success: ${upload_success}, failures: ${upload_failures}, skiped_files: ${skiped_files}" >> ${upload_err_log}
run_time=`expr ${finish_timestamp} - ${start_timestamp}`
echo "upload used ${run_time} seconds" >> ${upload_err_log}
if [ $run_time -gt 1800 -a $upload_failures -gt 5 -a ${upload_success} -lt 100 ]
then
	#上传超时报警
	send_warning "上传超时" "time: ${run_time}, suc: ${upload_success}, fail: ${upload_failures}, skip: ${skiped_files}, iplist: ${iplist}" 
fi

#upload_info_file 不要太长,保存100000条记录应该差不多了
file_entries=`wc -l ${upload_info_file} | awk '{print $1}'`
if [ $file_entries -gt 150000 ]
then
	sed -e '1,50000d' -i ${upload_info_file}
fi

file_entries=`wc -l ${upload_err_log} | awk '{print $1}'`
if [ $file_entries -gt 150000 ]
then
	sed -e '1,50000d' -i ${upload_err_log}
fi

#清除上传shell的pid文件
rm -f ${upload_process_pid}




