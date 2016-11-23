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

return _M