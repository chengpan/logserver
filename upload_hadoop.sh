#!/bin/bash

function send_warning()
{
	title=$1
	content=$2
	curl -H 'Accept:application/json' --data-urlencode "id=10075" --data-urlencode "title=${title}" --data-urlencode "content=${content}" http://106.75.0.234/monitor.cgi
}

download_dir="/data3/log_process/download/"
ufile_info_dir="/data4/log_process/upload/"
ufile_upload_tmp_dir=${ufile_info_dir}"upload_tmp/"
ufile_err_log=${ufile_info_dir}"err_log"
tmp_ufile_file_list=${ufile_info_dir}"tmp_ufile_file_list"
tmp_ufile_tgz_list=${ufile_info_dir}"tmp_ufile_tgz_list"
tar_failure_file_list=${ufile_info_dir}"tar_failure_file_list"
ufile_process_pid=${ufile_info_dir}"ufile_process_pid"
ufile_process_busy=${ufile_info_dir}"ufile_process_busy"
ufile_notify_server_url="http://106.75.0.234:80/ufile_record.lua"
ufile_check_upload_status_url="http://106.75.0.234:80/check_upload_status.lua"
ufile_bucket="cdnlogs"

#存放log及各种信息
[ -d ${ufile_info_dir} ] || mkdir ${ufile_info_dir}
[ -d ${ufile_upload_tmp_dir} ] || mkdir ${ufile_upload_tmp_dir}

#保证只有一个进程在上传
if [ -f ${ufile_process_pid} ]
then
	echo "${ufile_process_pid} exists" >> ${ufile_process_busy}
	date >> ${ufile_process_busy}
	pid=`cat ${ufile_process_pid}`
	found=`ps ax | awk '{ print $1 }' | grep -e "^${pid}$"`
	if [ -n "${found}" ]
	then
		echo "upload process exists! pid = ${pid}, this is serious !!!" >> ${ufile_process_busy}
		exit
	else
		echo "upload process doesnot exist! crashed ???" >> ${ufile_process_busy}
	fi
fi

echo $$ > ${ufile_process_pid}

echo "work starts here"
rm -rf ${HOME}/.ufile/mput

#查找上2/3小时之前的日志
rm -f ${tmp_ufile_file_list}
time_2str=`date -d "-2 hour" "+%Y%m%d%H"`
time_1str=`date -d "-1 hour" "+%Y%m%d%H"`
find ${download_dir} -type f \( -name "*${time_1str}*" -o -mmin +60 \) -fprint ${tmp_ufile_file_list}

declare -i ufile_success=0
declare -i ufile_failures=0

echo >> ${ufile_err_log}
echo "ufile started at : " >> ${ufile_err_log}
date >> ${ufile_err_log}
start_timestamp=`date +%s`
echo "total log files: " >> ${ufile_err_log}
wc ${tmp_ufile_file_list} -l >> ${ufile_err_log}

#把所有新生产的文件都放到临时目录去sync
#使用多进程,打包太慢了
tmp_fifo="/tmp/$$.fifo"
mkfifo ${tmp_fifo}
exec 6<>${tmp_fifo}
rm -f ${tmp_fifo}
for ((i=0;i<5;i++))
do
	echo ""
done >&6
while read file
do
	upload_status=`curl --silent ${ufile_check_upload_status_url}"?file="${file} | grep "found_in_db"`
	if [ -n "${upload_status}" ]
	then
		rm -f ${file}
		continue
	fi

	file_name=`basename ${file}`
	file_dir=`dirname ${file}`
	file_dir_name=`basename ${file_dir}`

	gz_file_dir=${ufile_upload_tmp_dir}${file_dir_name}"/"
	gz_file_path=${gz_file_dir}${file_name}
	[ -d ${gz_file_dir} ] || mkdir -p ${gz_file_dir}

	left_file=`find ${gz_file_dir} -type f -name "*.gz" | wc -l`
	if [ ${left_file} -eq 0 ]
	then
		split ${file} -b 200M -d -a 4 ${gz_file_path}  2>>${ufile_err_log}
		if [ $? -ne 0 ]
		then
			echo "split ${file} failed" >> ${ufile_err_log}
			rm -rf ${gz_file_dir}
		fi
	fi

done < ${tmp_ufile_file_list}

rm -f ${tmp_ufile_file_list}
find ${ufile_upload_tmp_dir} -type f ! -name "*.gz" -fprint ${tmp_ufile_file_list}
wc -l ${tmp_ufile_file_list}
while read file
do
	read -u6
	{
		gzip --fast ${file}
		if [ $? -ne 0 ]
		then
			echo "gzip --fast ${file} failed, try again" >> ${ufile_err_log}
			gzip --fast ${file}
		fi
		echo "" >&6
	}&
done < ${tmp_ufile_file_list}
wait

#I don't know why I do it again
rm -f ${tmp_ufile_file_list}
find ${ufile_upload_tmp_dir} -type f ! -name "*.gz" -fprint ${tmp_ufile_file_list}
wc -l ${tmp_ufile_file_list}
while read file
do
	read -u6
	{
		gzip --fast ${file}
		if [ $? -ne 0 ]
		then
			echo "gzip --fast ${file} failed, try again" >> ${ufile_err_log}
			gzip --fast ${file}
		fi
		echo "" >&6
	}&
done < ${tmp_ufile_file_list}
wait

exec 6>&-

find ${ufile_upload_tmp_dir} -type f ! -name "*.gz" -exec gzip --fast {} \;
find ${ufile_upload_tmp_dir} -type f ! -name "*.gz" -exec rm -f {} \;
echo "sync data at : " >> ${ufile_err_log}
date >> ${ufile_err_log}

#上传文件了！
/usr/local/bin/filemgr-linux64 --action sync --bucket ${ufile_bucket} --dir ${ufile_upload_tmp_dir} --trimpath ${ufile_upload_tmp_dir} >> ${ufile_err_log}

#查找ufile_upload_tmp_dir下的所有文件, 一一验证是否已经上传成功,成功就写入数据库并删除文件, 否则不删除文件
rm -f ${tmp_ufile_tgz_list}
find ${ufile_upload_tmp_dir} -type f -name "*.gz" -fprint ${tmp_ufile_tgz_list}

#检查该目录下的所有gz文件有没有上传成功
while read file
do
	file_name=`basename ${file}`
	file_dir=`dirname ${file}`
	file_dir_name=`basename ${file_dir}`

	file_key=${file_dir_name}"/"${file_name}
	found=`/usr/local/bin/filemgr-linux64 --action check --bucket ${ufile_bucket} --key ${file_key} | grep "ErrMsg"`
	if [ -z "${found}" ]
	then
		#found in ufile, upload success !
		notify_server=`curl --silent ${ufile_notify_server_url}"?file_key="${file_key} | grep "upload_success"`
		if [ -n "${notify_server}" ]
		then
			#echo "notify_server for ${file_key} succeed" >> ${ufile_err_log}
			let ufile_success++
			rm -f ${file}
		else
			echo "notify_server for ${file_key} failed !" >> ${ufile_err_log}
			let ufile_failures++
		fi
	else
		echo "${file_key} not found! in ufile cloud. this is WRONG !!!" >> ${ufile_err_log}
		let ufile_failures++
	fi		

done < ${tmp_ufile_tgz_list}

echo "finish sync and notify server at : " >> ${ufile_err_log}
date >> ${ufile_err_log}
finish_timestamp=`date +%s`
run_time=`expr ${finish_timestamp} - ${start_timestamp}`
echo "run_time: ${run_time}, success : ${ufile_success}, failures: ${ufile_failures}" >> ${ufile_err_log}

if [ ${ufile_failures} -gt 0 -o ${run_time} -gt 3600 ]
then
	send_warning "ufile上传" "run_time: ${run_time}, success : ${ufile_success}, failures: ${ufile_failures}"
fi

#清除上传shell的pid文件
rm -f ${ufile_process_pid}

#删除2天前的下载日志
time_str=`date -d "-2 day" "+%Y%m%d"`
[ -d ${download_dir}${time_str} ] && rm -rf ${download_dir}${time_str}
