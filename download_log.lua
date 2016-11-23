local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"
local shell = require "resty/shell"
local resty_string = require "resty/string"

local args = ngx.req.get_uri_args()
local id = tonumber(args["id"])

if not id then
	ngx.log(ngx.ERR, "no id")
	ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local query_sql = "select * from tb_hadoop_files where id = "..id
ngx.log(ngx.DEBUG, "query_sql: ", query_sql)

local db, err = mysql:new()
if not db then
	ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

db:set_timeout(1000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect(conf.hadoop_db)
if not ok then
	ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local res, err, errcode, sqlstate = db:query(query_sql)
if not res then
	ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	ngx.log(ngx.ERR, "query_sql: ", query_sql)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local ok, err = db:set_keepalive(10000, 100)
if not ok then
	ngx.log(ngx.ERR, "failed to set keepalive: ", err)
	db:close()
end

if #res ~= 1 then
	ngx.log(ngx.ERR, "no corresponding info found!")
	ngx.exit(ngx.HTTP_BAD_REQUEST)	
end

local hdfs_path = res[1].hdfs_path

ngx.log(ngx.DEBUG, "file for ", id, " is ", hdfs_path)

file_size = webhdfs.get_file_size(hdfs_path)

if file_size <= 0 then
	ngx.log(ngx.ERR, hdfs_path, " not found in hadoop")
	ngx.exit(ngx.HTTP_NOT_FOUND)
end

--确定是否是最后一个片段 最后一个片段不应该保留
segments = math.ceil(file_size/conf.segment_size)

local regex_expr = "^"..conf.hadoop_root.."(.*)$"
local m = ngx.re.match(hdfs_path, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "path not match regex: ", regex_expr, ", path: ", hdfs_path)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)	
end

local gz_relative_path = m[1]

local log_path = conf.gzip_log_dir..gz_relative_path
local gz_log_path = log_path..".gz"
ngx.log(ngx.DEBUG, "download from hadoop to ", log_path)

--curl --silent 'http://106.75.31.237:50070/webhdfs/v1/logs/20161123/api.dmzj.com/small_2016112308_access.log?op=OPEN' -L -o aa.log
local cmd = string.format("[ ! -f %s ] && mkdir -p `dirname %s`"
						.." && curl --silent 'http://10.9.101.54:50070/webhdfs/v1%s?op=OPEN' -L -o %s"
						.." && gzip --fast %s",
						gz_log_path,
						gz_log_path,
						hdfs_path,
						log_path,
						log_path)

ngx.log(ngx.DEBUG, "cmd: ", cmd)

local args = {socket = "unix:/tmp/shell.sock", timeout = 60000}
local status, out, err = shell.execute(cmd, args)
if status ~= 0 then
	ngx.log(ngx.ERR, "cmd: ", cmd, "status: ", status, ", out: ", out, ", err: ", err)
	shell.execute("rm -f "..log_path.."*", args)
end

local exec_location = "/"..gz_relative_path..".gz"
ngx.log(ngx.DEBUG, "localtion: ", exec_location)
return ngx.exec(exec_location)


