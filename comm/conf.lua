local _M = { _VERSION = '0.01', _AUTHOR = 'enoch' }

--域名和ip db
_M.hadoop_db =
{	
	host = "10.9.170.241",
	port = 3306,
	database = "ucdn",
	user = "root",
	password = "ucdnred@cat;;",
	max_packet_size = 1024 * 1024	
}

_M.hadoop_root = "/logs/"
_M.mysql_max_results = 500
_M.segment_size = 500*1024*1024
_M.log_download_host = "http://106.75.87.81"
_M.gzip_log_dir = "/data/log_server/logs/"
_M.gzip_download_location = "/logs/"
_M.download_whole_domains = {
	"img.antutu.com",
	"file.antutu.com",
	"mvvideo1.meitudata.com",
	"mvvideo2.meitudata.com",
	"mvvideo3.meitudata.com",
	"mvvideo4.meitudata.com",
	"mvvideo10.meitudata.com",
	"mvvideo11.meitudata.com"
}

return _M