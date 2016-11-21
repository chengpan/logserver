local _M = { _VERSION = '0.01', _AUTHOR = 'enoch' }

--域名和ip db
_M.domain_ip_db =
{	
	host = "172.23.184.201",
	port = 3306,
	database = "icdn",
	user = "ucloud",
	password = "ucloud.cn",
	max_packet_size = 1024 * 1024	
}

--日志分析结果db
_M.log_stats_db =
{	
	host = "172.23.184.203",
	port = 3306,
	database = "log",
	user = "ucloud",
	password = "ucloud.cn",
	max_packet_size = 1024 * 1024	
}

--下载的日志存储路径
_M.log_file_dir = '/data3/log_process/download/'

--ufile存储路径的前缀
_M.ufile_url_prefix = 'http://cdnlogs.ufile.ucloud.com.cn/' --源站地址

return _M