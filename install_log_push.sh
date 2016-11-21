download_script_url="http://106.75.0.234/upload_log.sh"
crontab_backup="/tmp/crontab.bak"
upload_sh_dir="/root/upload_log/"
upload_sh_path="/root/upload_log/upload_log.sh"
[ -d ${upload_sh_dir} ] || mkdir -p ${upload_sh_dir}
[ -f ${upload_sh_path} ] && rm -f ${upload_sh_path}
wget ${download_script_url} -O ${upload_sh_path}
[ $? -eq 0 ] || exit 1 

crontab -l | grep -v 'log push script daemon' | grep -v '/root/upload_log/upload_log.sh' > ${crontab_backup}
[ $? -eq 0 ] || exit 1
echo '#------------------------log push script daemon----------------------' >> ${crontab_backup}
[ $? -eq 0 ] || exit 1
echo '*/5 * * * * bash /root/upload_log/upload_log.sh' >> ${crontab_backup}
[ $? -eq 0 ] || exit 1
cat ${crontab_backup} | crontab -
[ $? -eq 0 ] || exit 1

