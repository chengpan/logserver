#!/bin/bash

if [ $# -ne 1 ]
then
	echo "wrong param number"
	exit
fi

file_list=$1

if [ ! -f ${file_list} ]
then
	echo "${file_list} not a file"
	exit
fi

nginx_put_dir="/data2/log_process/nginx_put_dir/"
download_dir="/data2/log_process/download/"
collect_log_dir="/data2/log_process/collect_log/"
process_pid=${collect_log_dir}"process_pid"
process_busy=${collect_log_dir}"process_busy"
collected_log_file=${collect_log_dir}"collected_log_file"
err_log=${collect_log_dir}"err_log"
tmp_file_list=${collect_log_dir}"tmp_file_list"

echo "subprocess start collecting ${file_list}" >> ${err_log}
date >> ${err_log}
wc -l ${file_list} >> ${err_log}

while read file 
do
	file_name=`basename ${file}`
	tmp_dir_name=`dirname ${file}`
	
	domain_name=`basename ${tmp_dir_name}`
	tmp_dir_name=`dirname ${tmp_dir_name}`

	log_date=`basename ${tmp_dir_name}`

	download_file_dir=${download_dir}${log_date}/${domain_name}/
	
	suffix=`echo ${file_name} | grep -E -o '_[0-9]*$'`
	download_file_name=`echo ${file_name} | sed -e "s/${suffix}//g"`

	time_min=`echo ${download_file_name} | grep -E -o "[0-9]{12}"`
	time_hour=`echo ${time_min} | grep -E -o "^[0-9]{10}"`
	download_file_name=`echo ${download_file_name} | sed "s/${time_min}/${time_hour}/g"`

	if [ -z ${download_file_name} ]
	then
		echo "${file} does not match pattern" >> ${err_log}
		continue
	fi

	download_file_path=${download_file_dir}${download_file_name}
	
	[ -d ${download_file_dir} ] || mkdir -p ${download_file_dir}

	[ -f ${file} ] && cat ${file} >> ${download_file_path}
	[ -f ${file} ] && rm -f ${file}
	#echo ${file} >> ${collected_log_file}
done < ${file_list}

rm -f ${file_list}
echo "subprocess finish collecting ${file_list}" >> ${err_log}
date >> ${err_log}


